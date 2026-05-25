import { useState, useEffect, useCallback, useRef } from 'react'
import { useAuth } from '../../contexts/AuthContext'
import { apiFetch } from '../../utils/api'
import { hydrateLocations, rehydrateLocations } from './locationHydration'
import { buildPayload, buildLocationPayload } from './buildPayload'
import type {
  ClientLocation,
  EncounterTableData, StoryNpcData,
  StoryData, SeedFact,
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
  const [hiddenFromPlayers, setHiddenFromPlayers] = useState(false)
  const [seedFacts, setSeedFacts] = useState<SeedFact[]>([])
  const [currentStoryId, setCurrentStoryId] = useState<number | undefined>(storyId)

  const [locations, setLocations] = useState<ClientLocation[]>([])
  const [encounterTables, setEncounterTables] = useState<EncounterTableData[]>([])
  const [npcs, setNpcs] = useState<StoryNpcData[]>([])

  const [seedFactsOpen, setSeedFactsOpen] = useState(true)
  const [locationsOpen, setLocationsOpen] = useState(false)
  const [encounterTablesOpen, setEncounterTablesOpen] = useState(false)
  const [npcsOpen, setNpcsOpen] = useState(false)
  const [expandedLocIdx, setExpandedLocIdx] = useState<number | null>(null)
  const [expandedTableIdx, setExpandedTableIdx] = useState<number | null>(null)

  const showFeedback = useCallback((type: 'success' | 'error', msg: string) => {
    setFeedback({ type, message: msg })
  }, [])
  const dismissFeedback = useCallback(() => setFeedback(null), [])

  const locationsRef = useRef(locations)
  locationsRef.current = locations

  const applyServerData = (data: StoryData, fresh = false) => {
    setTitle(data.title)
    setPreview(data.preview)
    setPremise(data.premise)
    setOpeningMessage(data.opening_message || '')
    setHiddenFromPlayers(!!data.hidden_from_players)
    setSeedFacts(Array.isArray(data.seed_facts) ? data.seed_facts : [])
    setLocations(fresh
      ? hydrateLocations(data.story_locations || [])
      : rehydrateLocations(data.story_locations || [], locationsRef.current)
    )
    setEncounterTables(data.encounter_tables || [])
    setNpcs(data.story_npcs || [])
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
    openingMessage, hiddenFromPlayers, seedFacts,
    currentStoryId, locations, encounterTables, npcs,
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
    hiddenFromPlayers, setHiddenFromPlayers,
    seedFacts, setSeedFacts,
    currentStoryId,
    locations, setLocations,
    encounterTables, setEncounterTables,
    npcs, setNpcs,
    seedFactsOpen, setSeedFactsOpen,
    locationsOpen, setLocationsOpen,
    encounterTablesOpen, setEncounterTablesOpen,
    npcsOpen, setNpcsOpen,
    expandedLocIdx, setExpandedLocIdx,
    expandedTableIdx, setExpandedTableIdx,
    duplicateNames, hasDuplicateNames,
    saveStory,
  }
}
