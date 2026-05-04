import { useState, useEffect, useCallback, useRef } from 'react'
import { useAuth } from '../../contexts/AuthContext'
import { apiFetch } from '../../utils/api'
import { hydrateLocations, rehydrateLocations } from './locationHydration'
import { buildPayload, buildLocationPayload } from './buildPayload'
import type {
  ClientLocation,
  EncounterTableData, StoryNpcData,
  StoryData, InitialContexts, SeedFact,
  TraversalCtx, CombatCtx, SocialCtx, ExplorationCtx, RestCtx, InventoryCtx,
} from './types'
import {
  emptyTraversalCtx, emptyCombatCtx, emptySocialCtx,
  emptyExplorationCtx, emptyRestCtx, emptyInventoryCtx,
} from './types'

export const useStoryEditorState = (mode: 'create' | 'edit', storyId?: number) => {
  const { user, loading: authLoading } = useAuth()

  const [loading, setLoading] = useState(mode === 'edit')
  const [saving, setSaving] = useState(false)
  const [feedback, setFeedback] = useState<{ type: 'success' | 'error'; message: string } | null>(null)

  const [title, setTitle] = useState('')
  const [preview, setPreview] = useState('')
  const [premise, setPremise] = useState('')
  const [openingMessage, setOpeningMessage] = useState('')
  const [seedFacts, setSeedFacts] = useState<SeedFact[]>([])
  const [initialSummary, setInitialSummary] = useState('')
  const [currentStoryId, setCurrentStoryId] = useState<number | undefined>(storyId)

  const [locations, setLocations] = useState<ClientLocation[]>([])
  const [encounterTables, setEncounterTables] = useState<EncounterTableData[]>([])
  const [npcs, setNpcs] = useState<StoryNpcData[]>([])

  const [icTraversal, setIcTraversal] = useState<TraversalCtx>(emptyTraversalCtx())
  const [icCombat, setIcCombat] = useState<CombatCtx>(emptyCombatCtx())
  const [icSocial, setIcSocial] = useState<SocialCtx>(emptySocialCtx())
  const [icExploration, setIcExploration] = useState<ExplorationCtx>(emptyExplorationCtx())
  const [icRest, setIcRest] = useState<RestCtx>(emptyRestCtx())
  const [icInventory, setIcInventory] = useState<InventoryCtx>(emptyInventoryCtx())

  const [seedFactsOpen, setSeedFactsOpen] = useState(true)
  const [locationsOpen, setLocationsOpen] = useState(false)
  const [encounterTablesOpen, setEncounterTablesOpen] = useState(false)
  const [npcsOpen, setNpcsOpen] = useState(false)
  const [initialContextsOpen, setInitialContextsOpen] = useState(false)
  const [icSubOpen, setIcSubOpen] = useState<Record<string, boolean>>({})
  const [expandedLocIdx, setExpandedLocIdx] = useState<number | null>(null)
  const [expandedTableIdx, setExpandedTableIdx] = useState<number | null>(null)

  const showFeedback = useCallback((type: 'success' | 'error', msg: string) => {
    setFeedback({ type, message: msg })
  }, [])
  const dismissFeedback = useCallback(() => setFeedback(null), [])

  const locationsRef = useRef(locations)
  locationsRef.current = locations

  const hydrateInitialContexts = (ic: InitialContexts) => {
    const t = ic.traversal_context || {}
    setIcTraversal({
      ...emptyTraversalCtx(),
      ...t,
      exits: Array.isArray(t.exits) ? t.exits : [],
      nearby_npcs: Array.isArray(t.nearby_npcs) ? t.nearby_npcs : [],
      points_of_interest: Array.isArray(t.points_of_interest) ? t.points_of_interest : [],
    })
    setIcCombat({ ...emptyCombatCtx(), ...(ic.combat_context || {}) })
    const s = ic.social_context || {}
    setIcSocial({
      ...emptySocialCtx(),
      ...s,
      npcs_present: Array.isArray(s.npcs_present) ? s.npcs_present : [],
    })
    const e = ic.exploration_context || {}
    setIcExploration({
      ...emptyExplorationCtx(),
      ...e,
      searched_areas: Array.isArray(e.searched_areas) ? e.searched_areas : [],
      discovered_items: Array.isArray(e.discovered_items) ? e.discovered_items : [],
      discovered_secrets: Array.isArray(e.discovered_secrets) ? e.discovered_secrets : [],
      pending_investigations: Array.isArray(e.pending_investigations) ? e.pending_investigations : [],
    })
    setIcRest({ ...emptyRestCtx(), ...(ic.rest_context || {}) })
    const inv = ic.inventory_context || {}
    setIcInventory({
      ...emptyInventoryCtx(),
      ...inv,
      recently_acquired: Array.isArray(inv.recently_acquired) ? inv.recently_acquired : [],
      notable_consumables_remaining: Array.isArray(inv.notable_consumables_remaining) ? inv.notable_consumables_remaining : [],
      equipped_changes: Array.isArray(inv.equipped_changes) ? inv.equipped_changes : [],
    })
  }

  const applyServerData = (data: StoryData, fresh = false) => {
    setTitle(data.title)
    setPreview(data.preview)
    setPremise(data.premise)
    setOpeningMessage(data.opening_message || '')
    setSeedFacts(Array.isArray(data.seed_facts) ? data.seed_facts : [])
    setInitialSummary(data.initial_summary || '')
    setLocations(fresh
      ? hydrateLocations(data.story_locations || [])
      : rehydrateLocations(data.story_locations || [], locationsRef.current)
    )
    setEncounterTables(data.encounter_tables || [])
    setNpcs(data.story_npcs || [])
    hydrateInitialContexts(data.initial_contexts || {})
  }

  useEffect(() => {
    if (mode !== 'edit' || !storyId || !user?.admin) return

    const loadStory = async () => {
      try {
        setLoading(true)
        const data: StoryData = await apiFetch(`/admin/stories/${storyId}.json`)
        applyServerData(data, true)
      } catch (err: any) {
        showFeedback('error', err.message)
      } finally {
        setLoading(false)
      }
    }

    loadStory()
  }, [mode, storyId, user])

  // ---- Duplicate name detection ----

  const duplicateNames = (() => {
    const counts = new Map<string, number>()
    locations.forEach(l => {
      if (l._destroy) return
      const key = l.name.trim().toLowerCase()
      if (!key) return
      counts.set(key, (counts.get(key) || 0) + 1)
    })
    const dupes = new Set<string>()
    counts.forEach((count, key) => { if (count > 1) dupes.add(key) })
    return dupes
  })()

  const hasDuplicateNames = duplicateNames.size > 0

  // ---- Save ----

  const getPayloadArgs = () => ({
    title, preview, premise,
    openingMessage, seedFacts,
    initialSummary,
    currentStoryId, locations, encounterTables, npcs,
    icTraversal, icCombat, icSocial, icExploration, icRest, icInventory,
  })

  const saveStory = async () => {
    if (hasDuplicateNames) {
      showFeedback('error', 'Location names must be unique. Fix duplicates before saving.')
      return
    }

    setSaving(true)
    try {
      if (mode === 'create' && !currentStoryId) {
        const payload = buildPayload(getPayloadArgs())
        const data: StoryData = await apiFetch('/admin/stories', {
          method: 'POST',
          body: JSON.stringify(payload),
        })
        window.location.href = `/admin/stories/${data.id}`
        return
      }

      const payload = buildPayload(getPayloadArgs())
      const data: StoryData = await apiFetch(`/admin/stories/${currentStoryId}`, {
        method: 'PATCH',
        body: JSON.stringify(payload),
      })
      applyServerData(data)

      showFeedback('success', 'Story saved successfully')
    } catch (err: any) {
      showFeedback('error', err.message)
    } finally {
      setSaving(false)
    }
  }

  return {
    user, authLoading, loading, saving, feedback, dismissFeedback,
    title, setTitle, preview, setPreview, premise, setPremise,
    openingMessage, setOpeningMessage,
    seedFacts, setSeedFacts,
    initialSummary, setInitialSummary,
    currentStoryId,
    locations, setLocations,
    encounterTables, setEncounterTables,
    npcs, setNpcs,
    icTraversal, setIcTraversal, icCombat, setIcCombat,
    icSocial, setIcSocial, icExploration, setIcExploration,
    icRest, setIcRest, icInventory, setIcInventory,
    seedFactsOpen, setSeedFactsOpen,
    locationsOpen, setLocationsOpen,
    encounterTablesOpen, setEncounterTablesOpen,
    npcsOpen, setNpcsOpen,
    initialContextsOpen, setInitialContextsOpen,
    icSubOpen, setIcSubOpen,
    expandedLocIdx, setExpandedLocIdx,
    expandedTableIdx, setExpandedTableIdx,
    duplicateNames, hasDuplicateNames,
    saveStory,
  }
}
