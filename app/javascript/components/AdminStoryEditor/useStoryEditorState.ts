import { useState, useEffect, useCallback, useRef } from 'react'
import { useAuth } from '../../contexts/AuthContext'
import { apiFetch } from '../../utils/api'
import { hydrateLocations, rehydrateLocations } from './locationHydration'
import { buildPayload, buildLocationPayload } from './buildPayload'
import type {
  ClientLocation,
  EncounterTableData, StoryNpcData, StoryClueData, StoryMilestoneData,
  StoryData, InitialContexts,
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
  const [enriching, setEnriching] = useState(false)
  const [feedback, setFeedback] = useState<{ type: 'success' | 'error'; message: string } | null>(null)

  const [title, setTitle] = useState('')
  const [preview, setPreview] = useState('')
  const [premise, setPremise] = useState('')
  const [initialSummary, setInitialSummary] = useState('')
  const [currentStoryId, setCurrentStoryId] = useState<number | undefined>(storyId)

  const [locations, setLocations] = useState<ClientLocation[]>([])
  const [encounterTables, setEncounterTables] = useState<EncounterTableData[]>([])
  const [npcs, setNpcs] = useState<StoryNpcData[]>([])
  const [clues, setClues] = useState<StoryClueData[]>([])
  const [milestones, setMilestones] = useState<StoryMilestoneData[]>([])

  const [icTraversal, setIcTraversal] = useState<TraversalCtx>(emptyTraversalCtx())
  const [icCombat, setIcCombat] = useState<CombatCtx>(emptyCombatCtx())
  const [icSocial, setIcSocial] = useState<SocialCtx>(emptySocialCtx())
  const [icExploration, setIcExploration] = useState<ExplorationCtx>(emptyExplorationCtx())
  const [icRest, setIcRest] = useState<RestCtx>(emptyRestCtx())
  const [icInventory, setIcInventory] = useState<InventoryCtx>(emptyInventoryCtx())

  const [locationsOpen, setLocationsOpen] = useState(false)
  const [encounterTablesOpen, setEncounterTablesOpen] = useState(false)
  const [npcsOpen, setNpcsOpen] = useState(false)
  const [cluesOpen, setCluesOpen] = useState(false)
  const [milestonesOpen, setMilestonesOpen] = useState(false)
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
    setInitialSummary(data.initial_summary || '')
    setLocations(fresh
      ? hydrateLocations(data.story_locations || [])
      : rehydrateLocations(data.story_locations || [], locationsRef.current)
    )
    setEncounterTables(data.encounter_tables || [])
    setNpcs(data.story_npcs || [])
    setClues(data.story_clues || [])
    setMilestones(data.story_milestones || [])
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
    title, preview, premise, initialSummary,
    currentStoryId, locations, encounterTables, npcs, clues, milestones,
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

  // ---- Enrich Story ----

  const enrichStory = async () => {
    if (!currentStoryId) return
    setEnriching(true)
    try {
      const result = await apiFetch(`/admin/stories/${currentStoryId}/enrich`, { method: 'POST' })
      if (result.error) {
        showFeedback('error', result.error)
        return
      }

      const existingNpcs = npcs.filter(n => n.source !== 'enricher' || n.id)
      const markedOldEnricher = existingNpcs.map(n =>
        n.source === 'enricher' && n.id ? { ...n, _destroy: true } : n
      )
      const newNpcs: StoryNpcData[] = (result.npcs || []).map((n: any) => ({
        source: 'enricher' as const, name: n.name, role: n.role,
        location_id: n.location_id, description: n.description,
        knowledge: n.knowledge, attitude: n.attitude, secret: n.secret,
      }))
      setNpcs([...markedOldEnricher, ...newNpcs])

      const existingClues = clues.filter(c => c.source !== 'enricher' || c.id)
      const markedOldClues = existingClues.map(c =>
        c.source === 'enricher' && c.id ? { ...c, _destroy: true } : c
      )
      const newClues: StoryClueData[] = (result.clues || []).map((c: any) => ({
        source: 'enricher' as const, title: c.title, description: c.description,
        discovery_method: c.discovery_method, location_id: c.location_id,
        npc_id: c.npc_id, prerequisite_clue_ids: c.prerequisite_clue_ids || [],
        reveals_secret: c.reveals_secret || '', difficulty: c.difficulty,
      }))
      setClues([...markedOldClues, ...newClues])

      const existingMs = milestones.filter(m => m.source !== 'enricher' || m.id)
      const markedOldMs = existingMs.map(m =>
        m.source === 'enricher' && m.id ? { ...m, _destroy: true } : m
      )
      const newMs: StoryMilestoneData[] = (result.milestones || []).map((m: any) => ({
        source: 'enricher' as const, title: m.title, description: m.description,
        trigger_clue_ids: m.trigger_clue_ids || [], consequence: m.consequence || '',
      }))
      setMilestones([...markedOldMs, ...newMs])

      const manifests: any[] = result.encounter_manifests || []
      if (manifests.length > 0) {
        setEncounterTables(prev => prev.map(table => ({
          ...table,
          encounter_table_entries: (table.encounter_table_entries || []).map(entry => {
            const match = manifests.find((m: any) =>
              m.encounter_entry_title?.toLowerCase() === entry.title?.toLowerCase()
            )
            if (match?.creatures?.length) {
              return { ...entry, creature_manifest: match.creatures }
            }
            return entry
          })
        })))
        setEncounterTablesOpen(true)
      }

      const proposedTables: any[] = result.proposed_encounter_tables || []
      if (proposedTables.length > 0) {
        const newTables: EncounterTableData[] = proposedTables.map((t: any) => ({
          name: t.name || 'Encounters',
          description: '',
          check_frequency_hours: t.check_frequency_hours || 4,
          encounter_chance: t.encounter_chance || 15,
          encounter_table_entries: (t.entries || []).map((e: any) => ({
            title: e.title || 'Encounter',
            description: e.description || '',
            entry_type: e.entry_type || 'ai_prompt',
            weight: e.weight || 1,
            creature_manifest: e.creatures || [],
          })),
        }))
        setEncounterTables(prev => [...prev, ...newTables])
        setEncounterTablesOpen(true)
      }

      const enrichedContexts = result.initial_contexts
      if (enrichedContexts && typeof enrichedContexts === 'object' && Object.keys(enrichedContexts).length > 0) {
        hydrateInitialContexts(enrichedContexts)
        setInitialContextsOpen(true)
      }

      setNpcsOpen(true)
      setCluesOpen(true)
      setMilestonesOpen(true)
      const extras: string[] = []
      if (manifests.length > 0) extras.push(`${manifests.length} encounter manifest(s)`)
      if (proposedTables.length > 0) extras.push(`${proposedTables.length} proposed encounter table(s)`)
      if (enrichedContexts && Object.keys(enrichedContexts).length > 0) extras.push('initial contexts')
      const extraMsg = extras.length > 0 ? ` Also applied: ${extras.join(', ')}.` : ''
      showFeedback('success', `Enrichment complete — review the proposed records below and Save to persist.${extraMsg}`)
    } catch (err: any) {
      showFeedback('error', `Enrichment failed: ${err.message}`)
    } finally {
      setEnriching(false)
    }
  }

  return {
    user, authLoading, loading, saving, enriching, feedback, dismissFeedback,
    title, setTitle, preview, setPreview, premise, setPremise,
    initialSummary, setInitialSummary,
    currentStoryId,
    locations, setLocations,
    encounterTables, setEncounterTables,
    npcs, setNpcs, clues, setClues, milestones, setMilestones,
    icTraversal, setIcTraversal, icCombat, setIcCombat,
    icSocial, setIcSocial, icExploration, setIcExploration,
    icRest, setIcRest, icInventory, setIcInventory,
    locationsOpen, setLocationsOpen,
    encounterTablesOpen, setEncounterTablesOpen,
    npcsOpen, setNpcsOpen, cluesOpen, setCluesOpen,
    milestonesOpen, setMilestonesOpen,
    initialContextsOpen, setInitialContextsOpen,
    icSubOpen, setIcSubOpen,
    expandedLocIdx, setExpandedLocIdx,
    expandedTableIdx, setExpandedTableIdx,
    duplicateNames, hasDuplicateNames,
    saveStory, enrichStory,
  }
}
