import { useState, useEffect, useCallback, useRef } from 'react'
import { useAuth } from '../../contexts/AuthContext'
import AdminNavbar from '../AdminNavbar/AdminNavbar'
import Login from '../Login'
import FlashMessage from '../FlashMessage'
import { apiFetch } from '../../utils/api'
import type {
  StoryLocationData, LocationConnectionData,
  EncounterTableData, EncounterTableEntryData,
  StoryNpcData, StoryClueData, StoryMilestoneData,
  NpcRole, NpcAttitude, DiscoveryMethod, ClueDifficulty,
} from '../../types'
import './AdminStoryEditor.scss'

// ---- Client-side identity layer for locations/connections ----

interface ClientConnection extends LocationConnectionData {
  _toRef: string
}

interface ClientLocation extends Omit<StoryLocationData, 'connections_from'> {
  _clientId: string
  connections_from: ClientConnection[]
}

const genClientId = () => crypto.randomUUID()

const hydrateLocations = (serverLocs: StoryLocationData[]): ClientLocation[] => {
  const locs: ClientLocation[] = serverLocs.map(loc => ({
    ...loc,
    _clientId: genClientId(),
    connections_from: (loc.connections_from || []).map(conn => ({
      ...conn,
      _toRef: '',
    })),
  }))

  const idToClientId = new Map<number, string>()
  locs.forEach(l => { if (l.id) idToClientId.set(l.id, l._clientId) })

  locs.forEach(l => {
    l.connections_from.forEach(conn => {
      if (conn.to_location_id) {
        conn._toRef = idToClientId.get(conn.to_location_id) || ''
      }
    })
  })

  return locs
}

const rehydrateLocations = (
  serverLocs: StoryLocationData[],
  prevLocs: ClientLocation[],
): ClientLocation[] => {
  const dbIdToClientId = new Map<number, string>()
  prevLocs.forEach(l => { if (l.id) dbIdToClientId.set(l.id, l._clientId) })
  const nameToClientId = new Map<string, string>()
  prevLocs.forEach(l => { if (!l._destroy && l.name) nameToClientId.set(l.name, l._clientId) })

  const locs: ClientLocation[] = serverLocs.map(loc => ({
    ...loc,
    _clientId: (loc.id ? dbIdToClientId.get(loc.id) : null) || nameToClientId.get(loc.name) || genClientId(),
    connections_from: (loc.connections_from || []).map(conn => ({
      ...conn,
      _toRef: '',
    })),
  }))

  const newIdToClientId = new Map<number, string>()
  locs.forEach(l => { if (l.id) newIdToClientId.set(l.id, l._clientId) })

  locs.forEach(l => {
    l.connections_from.forEach(conn => {
      if (conn.to_location_id) {
        conn._toRef = newIdToClientId.get(conn.to_location_id) || ''
      }
    })
  })

  return locs
}

// ---- Props & server data shape ----

interface AdminStoryEditorProps {
  mode: 'create' | 'edit'
  storyId?: number
}

interface StoryData {
  id: number
  title: string
  preview: string
  premise: string
  hook: string | null
  initial_context: string | null
  initial_summary: string | null
  story_locations?: StoryLocationData[]
  encounter_tables?: EncounterTableData[]
  story_npcs?: StoryNpcData[]
  story_clues?: StoryClueData[]
  story_milestones?: StoryMilestoneData[]
}

// ---- Constants ----

const TERRAIN_TYPES = ['road', 'trail', 'forest', 'mountain', 'swamp', 'desert', 'river', 'coast', 'urban', 'underground']
const NPC_ROLES: NpcRole[] = ['quest_giver', 'informant', 'antagonist', 'bystander', 'merchant']
const NPC_ATTITUDES: NpcAttitude[] = ['friendly', 'indifferent', 'unfriendly']
const DISCOVERY_METHODS: DiscoveryMethod[] = ['social', 'exploration', 'magic', 'combat', 'automatic']
const CLUE_DIFFICULTIES: ClueDifficulty[] = ['automatic', 'easy', 'moderate', 'hard']

// ---- Empty constructors ----

const emptyLocation = (): ClientLocation => ({
  name: '', description: '', starting: false,
  connections_from: [],
  _clientId: genClientId(),
})

const emptyConnection = (): ClientConnection => ({
  to_location_id: 0, distance_miles: 1, terrain_type: 'road', description: '',
  _toRef: '',
})

const emptyTable = (): EncounterTableData => ({
  name: '', description: '', check_frequency_hours: 4, encounter_chance: 15, encounter_table_entries: []
})

const emptyEntry = (): EncounterTableEntryData => ({
  title: '', description: '', entry_type: 'fixed', weight: 1
})

const emptyNpc = (): StoryNpcData => ({
  source: 'manual', name: '', role: 'bystander', description: '',
  knowledge: '', attitude: 'indifferent', secret: false,
})

const emptyClue = (): StoryClueData => ({
  source: 'manual', title: '', description: '', discovery_method: 'exploration',
  prerequisite_clue_ids: [], reveals_secret: '', difficulty: 'moderate',
})

const emptyMilestone = (): StoryMilestoneData => ({
  source: 'manual', title: '', description: '',
  trigger_clue_ids: [], consequence: '',
})

// ---- Component ----

export const AdminStoryEditor = ({ mode, storyId }: AdminStoryEditorProps) => {
  const { user, loading: authLoading } = useAuth()

  const [loading, setLoading] = useState(mode === 'edit')
  const [saving, setSaving] = useState(false)
  const [enriching, setEnriching] = useState(false)
  const [feedback, setFeedback] = useState<{ type: 'success' | 'error'; message: string } | null>(null)

  const [title, setTitle] = useState('')
  const [preview, setPreview] = useState('')
  const [premise, setPremise] = useState('')
  const [hook, setHook] = useState('')
  const [initialContext, setInitialContext] = useState('')
  const [initialSummary, setInitialSummary] = useState('')
  const [currentStoryId, setCurrentStoryId] = useState<number | undefined>(storyId)

  const [locations, setLocations] = useState<ClientLocation[]>([])
  const [encounterTables, setEncounterTables] = useState<EncounterTableData[]>([])
  const [npcs, setNpcs] = useState<StoryNpcData[]>([])
  const [clues, setClues] = useState<StoryClueData[]>([])
  const [milestones, setMilestones] = useState<StoryMilestoneData[]>([])

  const [locationsOpen, setLocationsOpen] = useState(false)
  const [encounterTablesOpen, setEncounterTablesOpen] = useState(false)
  const [npcsOpen, setNpcsOpen] = useState(false)
  const [cluesOpen, setCluesOpen] = useState(false)
  const [milestonesOpen, setMilestonesOpen] = useState(false)
  const [expandedLocIdx, setExpandedLocIdx] = useState<number | null>(null)
  const [expandedTableIdx, setExpandedTableIdx] = useState<number | null>(null)

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
    setHook(data.hook || '')
    setInitialContext(data.initial_context || '')
    setInitialSummary(data.initial_summary || '')
    setLocations(fresh
      ? hydrateLocations(data.story_locations || [])
      : rehydrateLocations(data.story_locations || [], locationsRef.current)
    )
    setEncounterTables(data.encounter_tables || [])
    setNpcs(data.story_npcs || [])
    setClues(data.story_clues || [])
    setMilestones(data.story_milestones || [])
  }

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

  // ---- Build nested attributes payload ----

  const buildLocationPayload = (skipUnresolved: boolean) => {
    const refToDbId = new Map<string, number>()
    locations.forEach(l => { if (l.id) refToDbId.set(l._clientId, l.id) })

    return locations.map(loc => {
      const locAttrs: Record<string, unknown> = {
        name: loc.name, description: loc.description, starting: loc.starting,
      }
      if (loc.id) locAttrs.id = loc.id
      if (loc._destroy) locAttrs._destroy = true

      locAttrs.connections_from_attributes = loc.connections_from
        .map(conn => {
          if (conn._destroy) {
            if (!conn.id) return null
            return { id: conn.id, _destroy: true }
          }
          const targetDbId = refToDbId.get(conn._toRef)
          if (!targetDbId) {
            if (skipUnresolved) return null
            return null
          }
          const connAttrs: Record<string, unknown> = {
            to_location_id: targetDbId,
            distance_miles: conn.distance_miles,
            terrain_type: conn.terrain_type,
            description: conn.description || '',
          }
          if (conn.id) connAttrs.id = conn.id
          return connAttrs
        })
        .filter(Boolean)

      return locAttrs
    })
  }

  const buildPayload = (skipUnresolvedConns = false) => {
    const story: Record<string, unknown> = {
      title, preview, premise, hook,
      initial_context: initialContext,
      initial_summary: initialSummary,
    }

    if (currentStoryId) {
      story.story_locations_attributes = buildLocationPayload(skipUnresolvedConns)

      story.encounter_tables_attributes = encounterTables.map(table => {
        const tAttrs: Record<string, unknown> = {
          name: table.name, description: table.description,
          check_frequency_hours: table.check_frequency_hours,
          encounter_chance: table.encounter_chance,
        }
        if (table.id) tAttrs.id = table.id
        if (table._destroy) tAttrs._destroy = true

        tAttrs.encounter_table_entries_attributes = (table.encounter_table_entries || []).map(entry => {
          const eAttrs: Record<string, unknown> = {
            title: entry.title, description: entry.description,
            entry_type: entry.entry_type, weight: entry.weight,
            terrain_types: entry.terrain_types || '',
            min_party_level: entry.min_party_level,
            max_party_level: entry.max_party_level,
          }
          if (entry.id) eAttrs.id = entry.id
          if (entry._destroy) eAttrs._destroy = true
          return eAttrs
        })

        return tAttrs
      })

      story.story_npcs_attributes = npcs.map(npc => {
        const attrs: Record<string, unknown> = {
          source: npc.source, name: npc.name, role: npc.role,
          location_id: npc.location_id || null, description: npc.description,
          knowledge: npc.knowledge, attitude: npc.attitude, secret: npc.secret,
        }
        if (npc.id) attrs.id = npc.id
        if (npc._destroy) attrs._destroy = true
        return attrs
      })

      story.story_clues_attributes = clues.map(clue => {
        const attrs: Record<string, unknown> = {
          source: clue.source, title: clue.title, description: clue.description,
          discovery_method: clue.discovery_method, location_id: clue.location_id || null,
          npc_id: clue.npc_id || null, prerequisite_clue_ids: clue.prerequisite_clue_ids,
          reveals_secret: clue.reveals_secret, difficulty: clue.difficulty,
        }
        if (clue.id) attrs.id = clue.id
        if (clue._destroy) attrs._destroy = true
        return attrs
      })

      story.story_milestones_attributes = milestones.map(ms => {
        const attrs: Record<string, unknown> = {
          source: ms.source, title: ms.title, description: ms.description,
          trigger_clue_ids: ms.trigger_clue_ids, consequence: ms.consequence,
        }
        if (ms.id) attrs.id = ms.id
        if (ms._destroy) attrs._destroy = true
        return attrs
      })
    }

    return { story }
  }

  // ---- Save (with two-phase for connections to unsaved locations) ----

  const hasUnresolvedConnections = () => {
    const refToDbId = new Map<string, number>()
    locations.forEach(l => { if (l.id) refToDbId.set(l._clientId, l.id) })

    return locations.some(l =>
      !l._destroy && l.connections_from.some(c =>
        !c._destroy && c._toRef && !refToDbId.has(c._toRef)
      )
    )
  }

  const saveStory = async () => {
    if (hasDuplicateNames) {
      showFeedback('error', 'Location names must be unique. Fix duplicates before saving.')
      return
    }

    setSaving(true)
    try {
      if (mode === 'create' && !currentStoryId) {
        const payload = buildPayload()
        const data: StoryData = await apiFetch('/admin/stories', {
          method: 'POST',
          body: JSON.stringify(payload),
        })
        window.location.href = `/admin/stories/${data.id}`
        return
      }

      const needsTwoPhase = hasUnresolvedConnections()

      if (needsTwoPhase) {
        const phase1 = buildPayload(true)
        const data1: StoryData = await apiFetch(`/admin/stories/${currentStoryId}`, {
          method: 'PATCH',
          body: JSON.stringify(phase1),
        })

        const serverLocs = rehydrateLocations(data1.story_locations || [], locations)
        setLocations(serverLocs)
        locationsRef.current = serverLocs

        const deferredConnsByRef = new Map<string, ClientConnection[]>()
        const refToDbId = new Map<string, number>()
        locations.forEach(l => { if (l.id) refToDbId.set(l._clientId, l.id) })

        locations.forEach(loc => {
          if (loc._destroy) return
          loc.connections_from.forEach(conn => {
            if (conn._destroy || !conn._toRef || conn.id) return
            if (refToDbId.has(conn._toRef)) return
            const arr = deferredConnsByRef.get(loc._clientId) || []
            arr.push(conn)
            deferredConnsByRef.set(loc._clientId, arr)
          })
        })

        const newRefToDbId = new Map<string, number>()
        serverLocs.forEach(l => { if (l.id) newRefToDbId.set(l._clientId, l.id) })

        const phase2LocAttrs = Array.from(deferredConnsByRef.entries())
          .map(([fromRef, conns]) => {
            const fromDbId = newRefToDbId.get(fromRef)
            if (!fromDbId) return null
            const resolvedConns = conns
              .map(c => {
                const toDbId = newRefToDbId.get(c._toRef)
                if (!toDbId) return null
                return {
                  to_location_id: toDbId,
                  distance_miles: c.distance_miles,
                  terrain_type: c.terrain_type,
                  description: c.description || '',
                }
              })
              .filter(Boolean)
            if (resolvedConns.length === 0) return null
            return { id: fromDbId, connections_from_attributes: resolvedConns }
          })
          .filter(Boolean)

        if (phase2LocAttrs.length > 0) {
          const phase2 = { story: { story_locations_attributes: phase2LocAttrs } }
          const data2: StoryData = await apiFetch(`/admin/stories/${currentStoryId}`, {
            method: 'PATCH',
            body: JSON.stringify(phase2),
          })
          applyServerData(data2)
        } else {
          applyServerData(data1)
        }
      } else {
        const payload = buildPayload()
        const data: StoryData = await apiFetch(`/admin/stories/${currentStoryId}`, {
          method: 'PATCH',
          body: JSON.stringify(payload),
        })
        applyServerData(data)
      }

      showFeedback('success', 'Story saved successfully')
    } catch (err: any) {
      showFeedback('error', err.message)
    } finally {
      setSaving(false)
    }
  }

  // ---- Location helpers ----

  const updateLocation = (idx: number, patch: Partial<ClientLocation>) => {
    setLocations(prev => prev.map((l, i) => i === idx ? { ...l, ...patch } : l))
  }

  const setStartingLocation = (idx: number) => {
    setLocations(prev => prev.map((l, i) => ({ ...l, starting: i === idx })))
  }

  const removeLocation = (idx: number) => {
    setLocations(prev => {
      const loc = prev[idx]
      const removedRef = loc._clientId

      const updated = loc.id
        ? prev.map((l, i) => i === idx ? { ...l, _destroy: true } : l)
        : prev.filter((_, i) => i !== idx)

      return updated.map(l => ({
        ...l,
        connections_from: l.connections_from.map(c =>
          c._toRef === removedRef ? { ...c, _destroy: true } : c
        ),
      }))
    })
  }

  const addConnection = (locIdx: number) => {
    setLocations(prev => prev.map((l, i) =>
      i === locIdx ? { ...l, connections_from: [...l.connections_from, emptyConnection()] } : l
    ))
  }

  const updateConnection = (locIdx: number, connIdx: number, patch: Partial<ClientConnection>) => {
    setLocations(prev => prev.map((l, li) => {
      if (li !== locIdx) return l
      const conns = l.connections_from.map((c, ci) =>
        ci === connIdx ? { ...c, ...patch } : c
      )
      return { ...l, connections_from: conns }
    }))
  }

  const removeConnection = (locIdx: number, connIdx: number) => {
    setLocations(prev => prev.map((l, li) => {
      if (li !== locIdx) return l
      const conn = l.connections_from[connIdx]
      if (conn?.id) {
        const conns = l.connections_from.map((c, ci) =>
          ci === connIdx ? { ...c, _destroy: true } : c
        )
        return { ...l, connections_from: conns }
      }
      return { ...l, connections_from: l.connections_from.filter((_, ci) => ci !== connIdx) }
    }))
  }

  // ---- Incoming connections (bidirectional, works for unsaved locations) ----

  const incomingConnections = (loc: ClientLocation) => {
    const incoming: { fromName: string; distance_miles: number; terrain_type: string }[] = []
    locations.forEach(other => {
      if (other._destroy || other._clientId === loc._clientId) return
      other.connections_from.forEach(conn => {
        if (conn._destroy || conn._toRef !== loc._clientId) return
        incoming.push({
          fromName: other.name,
          distance_miles: conn.distance_miles,
          terrain_type: conn.terrain_type,
        })
      })
    })
    return incoming
  }

  // ---- Encounter table helpers ----

  const updateTable = (idx: number, patch: Partial<EncounterTableData>) => {
    setEncounterTables(prev => prev.map((t, i) => i === idx ? { ...t, ...patch } : t))
  }

  const removeTable = (idx: number) => {
    const table = encounterTables[idx]
    if (table.id) {
      updateTable(idx, { _destroy: true })
    } else {
      setEncounterTables(prev => prev.filter((_, i) => i !== idx))
    }
  }

  const addEntry = (tableIdx: number) => {
    setEncounterTables(prev => prev.map((t, i) =>
      i === tableIdx ? { ...t, encounter_table_entries: [...(t.encounter_table_entries || []), emptyEntry()] } : t
    ))
  }

  const updateEntry = (tableIdx: number, entryIdx: number, patch: Partial<EncounterTableEntryData>) => {
    setEncounterTables(prev => prev.map((t, ti) => {
      if (ti !== tableIdx) return t
      const entries = (t.encounter_table_entries || []).map((e, ei) =>
        ei === entryIdx ? { ...e, ...patch } : e
      )
      return { ...t, encounter_table_entries: entries }
    }))
  }

  const removeEntry = (tableIdx: number, entryIdx: number) => {
    setEncounterTables(prev => prev.map((t, ti) => {
      if (ti !== tableIdx) return t
      const entry = (t.encounter_table_entries || [])[entryIdx]
      if (entry?.id) {
        const entries = (t.encounter_table_entries || []).map((e, ei) =>
          ei === entryIdx ? { ...e, _destroy: true } : e
        )
        return { ...t, encounter_table_entries: entries }
      }
      return { ...t, encounter_table_entries: (t.encounter_table_entries || []).filter((_, ei) => ei !== entryIdx) }
    }))
  }

  // ---- NPC helpers ----

  const updateNpc = (idx: number, patch: Partial<StoryNpcData>) => {
    setNpcs(prev => prev.map((n, i) => i === idx ? { ...n, ...patch } : n))
  }

  const removeNpc = (idx: number) => {
    const npc = npcs[idx]
    if (npc.id) {
      updateNpc(idx, { _destroy: true })
    } else {
      setNpcs(prev => prev.filter((_, i) => i !== idx))
    }
  }

  // ---- Clue helpers ----

  const updateClue = (idx: number, patch: Partial<StoryClueData>) => {
    setClues(prev => prev.map((c, i) => i === idx ? { ...c, ...patch } : c))
  }

  const removeClue = (idx: number) => {
    const clue = clues[idx]
    if (clue.id) {
      updateClue(idx, { _destroy: true })
    } else {
      setClues(prev => prev.filter((_, i) => i !== idx))
    }
  }

  // ---- Milestone helpers ----

  const updateMilestone = (idx: number, patch: Partial<StoryMilestoneData>) => {
    setMilestones(prev => prev.map((m, i) => i === idx ? { ...m, ...patch } : m))
  }

  const removeMilestone = (idx: number) => {
    const ms = milestones[idx]
    if (ms.id) {
      updateMilestone(idx, { _destroy: true })
    } else {
      setMilestones(prev => prev.filter((_, i) => i !== idx))
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

      setNpcsOpen(true)
      setCluesOpen(true)
      setMilestonesOpen(true)
      showFeedback('success', 'Enrichment complete — review the proposed records below and Save to persist.')
    } catch (err: any) {
      showFeedback('error', `Enrichment failed: ${err.message}`)
    } finally {
      setEnriching(false)
    }
  }

  // ---- Render ----

  if (authLoading) return <div className="app">Loading...</div>
  if (!user) return <Login />
  if (!user.admin) {
    return (
      <div className="app">
        <AdminNavbar active="stories" />
        <p className="feedback-error">Admin access required.</p>
      </div>
    )
  }

  if (loading) {
    return (
      <div className="app">
        <AdminNavbar active="stories" />
        <p style={{ padding: '20px' }}>Loading story...</p>
      </div>
    )
  }

  const isNew = mode === 'create' && !currentStoryId
  const canSave = title.trim() && preview.trim() && premise.trim() && !hasDuplicateNames
  const isEditMode = !!currentStoryId
  const visibleLocations = locations.filter(l => !l._destroy)
  const savedLocations = locations.filter(l => l.id && !l._destroy)
  const savedNpcs = npcs.filter(n => n.id && !n._destroy)
  const savedClues = clues.filter(c => c.id && !c._destroy)

  return (
    <div className="app">
      <AdminNavbar active="stories" />

      <div className="admin-story-editor">
        <div className="editor-top">
          <a href="/admin/stories" className="back-link">&larr; Back to Stories</a>
          <h1>{isNew ? 'New Story' : `Edit: ${title}`}</h1>
        </div>

        {feedback && (
          <FlashMessage
            type={feedback.type}
            message={feedback.message}
            onDismiss={dismissFeedback}
          />
        )}

        {/* Story fields */}
        <div className="form-field">
          <label htmlFor="story-title">Title</label>
          <input type="text" id="story-title" value={title}
            onChange={e => setTitle(e.target.value)} placeholder="Story title" />
        </div>

        <div className="form-field">
          <label htmlFor="story-preview">Preview (shown to players)</label>
          <textarea id="story-preview" value={preview}
            onChange={e => setPreview(e.target.value)} rows={3}
            placeholder="A brief teaser for the player..." />
        </div>

        <div className="form-field">
          <label htmlFor="story-premise">Premise (full story, admin only)</label>
          <textarea id="story-premise" value={premise}
            onChange={e => setPremise(e.target.value)} rows={6}
            placeholder="The full premise and plot details..." />
        </div>

        <div className="form-field">
          <label htmlFor="story-hook">Hook (spoiler-free player-facing intro)</label>
          <textarea id="story-hook" value={hook}
            onChange={e => setHook(e.target.value)} rows={4}
            placeholder="A spoiler-free description of the starting situation..." />
        </div>

        <div className="form-field">
          <label htmlFor="story-initial-context">Initial Context (opening scene)</label>
          <textarea id="story-initial-context" value={initialContext}
            onChange={e => setInitialContext(e.target.value)} rows={4}
            placeholder="Where is the player? What's happening?..." />
        </div>

        <div className="form-field">
          <label htmlFor="story-initial-summary">Initial Summary (story-so-far seed)</label>
          <textarea id="story-initial-summary" value={initialSummary}
            onChange={e => setInitialSummary(e.target.value)} rows={4}
            placeholder="A brief narrative summary of where the story begins..." />
        </div>

        {/* ---- Enrich Story button ---- */}
        {isEditMode && (
          <div className="enrich-section">
            <button className="btn-enrich" onClick={enrichStory} disabled={enriching || !premise.trim()}>
              {enriching ? 'Enriching...' : 'Enrich Story'}
            </button>
            <span className="enrich-hint">
              AI parses the premise into structured NPCs, clues, and milestones. Review before saving.
            </span>
          </div>
        )}

        {/* ---- Locations ---- */}
        {isEditMode && (
          <div className="collapsible-section">
            <button className="section-toggle" onClick={() => setLocationsOpen(!locationsOpen)}>
              <span className="toggle-icon">{locationsOpen ? '▾' : '▸'}</span>
              Locations ({visibleLocations.length})
            </button>

            {locationsOpen && (
              <div className="section-body">
                <p className="section-hint">
                  Define named locations for this story. Mark one as the starting location.
                  Connect locations with distances for travel resolution.
                </p>

                {visibleLocations.length === 0 && (
                  <p className="empty-hint">No locations yet.</p>
                )}

                {locations.map((loc, locIdx) => {
                  if (loc._destroy) return null
                  const isExpanded = expandedLocIdx === locIdx
                  const visibleConns = loc.connections_from.filter(c => !c._destroy)
                  const incoming = incomingConnections(loc)
                  const isDupeName = loc.name.trim() !== '' && duplicateNames.has(loc.name.trim().toLowerCase())
                  return (
                    <div key={loc._clientId} className="nested-card">
                      <div className="nested-card-header">
                        <button className="expand-btn" onClick={() => setExpandedLocIdx(isExpanded ? null : locIdx)}>
                          {isExpanded ? '▾' : '▸'}
                        </button>
                        <input type="text"
                          className={`inline-name ${isDupeName ? 'name-duplicate' : ''}`}
                          value={loc.name}
                          onChange={e => updateLocation(locIdx, { name: e.target.value })}
                          placeholder="Location name" />
                        {isDupeName && <span className="dup-warning" title="Duplicate name">dup</span>}
                        {!loc.id && <span className="unsaved-badge">new</span>}
                        <label className="starting-label">
                          <input type="radio" name="starting-location"
                            checked={loc.starting}
                            onChange={() => setStartingLocation(locIdx)} />
                          Start
                        </label>
                        <button className="btn-remove" onClick={() => removeLocation(locIdx)}>&#x2715;</button>
                      </div>

                      {isExpanded && (
                        <div className="nested-card-body">
                          <textarea value={loc.description || ''} rows={2}
                            onChange={e => updateLocation(locIdx, { description: e.target.value })}
                            placeholder="Location description..." />

                          <div className="connections-section">
                            <strong>Connections</strong>
                            {visibleConns.length === 0 && incoming.length === 0 && <p className="empty-hint">No connections.</p>}
                            {loc.connections_from.map((conn, connIdx) => {
                              if (conn._destroy) return null
                              return (
                                <div key={conn.id || `conn-${connIdx}`} className="connection-row">
                                  <span className="conn-direction" title="Outgoing">&rarr;</span>
                                  <select value={conn._toRef || ''}
                                    onChange={e => updateConnection(locIdx, connIdx, { _toRef: e.target.value })}>
                                    <option value="">&mdash; destination &mdash;</option>
                                    {visibleLocations.filter(vl => vl._clientId !== loc._clientId).map(vl => (
                                      <option key={vl._clientId} value={vl._clientId}>
                                        {vl.name || '(unnamed)'}{!vl.id ? ' *' : ''}
                                      </option>
                                    ))}
                                  </select>
                                  <input type="number" className="dist-input" value={conn.distance_miles}
                                    onChange={e => updateConnection(locIdx, connIdx, { distance_miles: Number(e.target.value) })}
                                    min={0.1} step={0.1} />
                                  <span className="unit">mi</span>
                                  <select value={conn.terrain_type}
                                    onChange={e => updateConnection(locIdx, connIdx, { terrain_type: e.target.value })}>
                                    {TERRAIN_TYPES.map(t => <option key={t} value={t}>{t}</option>)}
                                  </select>
                                  <button className="btn-remove-sm" onClick={() => removeConnection(locIdx, connIdx)}>&#x2715;</button>
                                </div>
                              )
                            })}
                            {incoming.map((inc, i) => (
                              <div key={`inc-${i}`} className="connection-row incoming">
                                <span className="conn-direction" title="Incoming (managed from the other location)">&larr;</span>
                                <span className="incoming-label">{inc.fromName || '(unnamed)'}</span>
                                <span className="dist-display">{inc.distance_miles} mi</span>
                                <span className="terrain-display">{inc.terrain_type}</span>
                              </div>
                            ))}
                            <button className="btn-add-sm" onClick={() => addConnection(locIdx)}>+ Connection</button>
                          </div>
                        </div>
                      )}
                    </div>
                  )
                })}

                <button className="btn-add" onClick={() => setLocations(prev => [...prev, emptyLocation()])}>
                  + Add Location
                </button>
              </div>
            )}
          </div>
        )}

        {/* ---- Encounter Tables ---- */}
        {isEditMode && (
          <div className="collapsible-section">
            <button className="section-toggle" onClick={() => setEncounterTablesOpen(!encounterTablesOpen)}>
              <span className="toggle-icon">{encounterTablesOpen ? '▾' : '▸'}</span>
              Encounter Tables ({encounterTables.filter(t => !t._destroy).length})
            </button>

            {encounterTablesOpen && (
              <div className="section-body">
                <p className="section-hint">
                  Define encounter tables for this story. Each table has a chance and frequency for random encounter checks.
                  Entries can be fixed text or AI-powered prompts.
                </p>

                {encounterTables.filter(t => !t._destroy).length === 0 && (
                  <p className="empty-hint">No encounter tables. A global default will be used if available.</p>
                )}

                {encounterTables.map((table, tableIdx) => {
                  if (table._destroy) return null
                  const isExpanded = expandedTableIdx === tableIdx
                  const visibleEntries = (table.encounter_table_entries || []).filter(e => !e._destroy)
                  return (
                    <div key={table.id || `table-${tableIdx}`} className="nested-card">
                      <div className="nested-card-header">
                        <button className="expand-btn" onClick={() => setExpandedTableIdx(isExpanded ? null : tableIdx)}>
                          {isExpanded ? '▾' : '▸'}
                        </button>
                        <input type="text" className="inline-name" value={table.name}
                          onChange={e => updateTable(tableIdx, { name: e.target.value })}
                          placeholder="Table name (e.g. Road Encounters)" />
                        <span className="table-meta">
                          {table.encounter_chance}% / {table.check_frequency_hours}h
                        </span>
                        <button className="btn-remove" onClick={() => removeTable(tableIdx)}>&#x2715;</button>
                      </div>

                      {isExpanded && (
                        <div className="nested-card-body">
                          <div className="table-config-row">
                            <div className="form-field compact">
                              <label>Chance (%)</label>
                              <input type="number" value={table.encounter_chance} min={0} max={100}
                                onChange={e => updateTable(tableIdx, { encounter_chance: Number(e.target.value) })} />
                            </div>
                            <div className="form-field compact">
                              <label>Frequency (hours)</label>
                              <input type="number" value={table.check_frequency_hours} min={1}
                                onChange={e => updateTable(tableIdx, { check_frequency_hours: Number(e.target.value) })} />
                            </div>
                          </div>
                          <textarea value={table.description || ''} rows={2}
                            onChange={e => updateTable(tableIdx, { description: e.target.value })}
                            placeholder="Table description (optional)..." />

                          <div className="entries-section">
                            <strong>Entries ({visibleEntries.length})</strong>
                            {visibleEntries.length === 0 && <p className="empty-hint">No entries yet.</p>}
                            {(table.encounter_table_entries || []).map((entry, entryIdx) => {
                              if (entry._destroy) return null
                              return (
                                <div key={entry.id || `entry-${entryIdx}`} className="entry-card">
                                  <div className="entry-header">
                                    <input type="text" className="inline-name" value={entry.title}
                                      onChange={e => updateEntry(tableIdx, entryIdx, { title: e.target.value })}
                                      placeholder="Entry title" />
                                    <div className="entry-type-toggle">
                                      <button
                                        className={`type-btn ${entry.entry_type === 'fixed' ? 'active' : ''}`}
                                        onClick={() => updateEntry(tableIdx, entryIdx, { entry_type: 'fixed' })}>
                                        Fixed
                                      </button>
                                      <button
                                        className={`type-btn ${entry.entry_type === 'ai_prompt' ? 'active' : ''}`}
                                        onClick={() => updateEntry(tableIdx, entryIdx, { entry_type: 'ai_prompt' })}>
                                        AI
                                      </button>
                                    </div>
                                    <label className="weight-label">
                                      W:
                                      <input type="number" className="weight-input" value={entry.weight}
                                        min={1} onChange={e => updateEntry(tableIdx, entryIdx, { weight: Number(e.target.value) })} />
                                    </label>
                                    <button className="btn-remove-sm" onClick={() => removeEntry(tableIdx, entryIdx)}>&#x2715;</button>
                                  </div>
                                  <textarea value={entry.description} rows={2}
                                    onChange={e => updateEntry(tableIdx, entryIdx, { description: e.target.value })}
                                    placeholder={entry.entry_type === 'fixed'
                                      ? 'Full encounter description...'
                                      : 'AI prompt hint — the AI will expand this into a scene...'} />
                                </div>
                              )
                            })}
                            <button className="btn-add-sm" onClick={() => addEntry(tableIdx)}>+ Add Entry</button>
                          </div>
                        </div>
                      )}
                    </div>
                  )
                })}

                <button className="btn-add" onClick={() => setEncounterTables(prev => [...prev, emptyTable()])}>
                  + Add Encounter Table
                </button>
              </div>
            )}
          </div>
        )}

        {/* ---- NPCs ---- */}
        {isEditMode && (
          <div className="collapsible-section">
            <button className="section-toggle" onClick={() => setNpcsOpen(!npcsOpen)}>
              <span className="toggle-icon">{npcsOpen ? '▾' : '▸'}</span>
              NPCs ({npcs.filter(n => !n._destroy).length})
            </button>

            {npcsOpen && (
              <div className="section-body">
                <p className="section-hint">
                  Named characters the player may encounter. The Enricher can auto-extract these from the premise.
                </p>

                {npcs.filter(n => !n._destroy).length === 0 && (
                  <p className="empty-hint">No NPCs yet. Use "Enrich Story" or add manually.</p>
                )}

                {npcs.map((npc, idx) => {
                  if (npc._destroy) return null
                  const isAi = npc.source === 'enricher' || npc.source === 'embellisher'
                  return (
                    <div key={npc.id || `npc-${idx}`} className={`nested-card ${isAi ? 'ai-sourced' : ''}`}>
                      <div className="nested-card-header">
                        {isAi && <span className="source-badge">{npc.source}</span>}
                        <input type="text" className="inline-name" value={npc.name}
                          onChange={e => updateNpc(idx, { name: e.target.value })}
                          placeholder="NPC name" />
                        <select className="compact-select" value={npc.role}
                          onChange={e => updateNpc(idx, { role: e.target.value as NpcRole })}>
                          {NPC_ROLES.map(r => <option key={r} value={r}>{r.replace('_', ' ')}</option>)}
                        </select>
                        <select className="compact-select" value={npc.attitude}
                          onChange={e => updateNpc(idx, { attitude: e.target.value as NpcAttitude })}>
                          {NPC_ATTITUDES.map(a => <option key={a} value={a}>{a}</option>)}
                        </select>
                        <button className="btn-remove" onClick={() => removeNpc(idx)}>&#x2715;</button>
                      </div>
                      <div className="nested-card-body">
                        <div className="inline-row">
                          <select value={npc.location_id || ''} onChange={e => updateNpc(idx, { location_id: Number(e.target.value) || null })}>
                            <option value="">-- location --</option>
                            {savedLocations.map(sl => <option key={sl.id} value={sl.id}>{sl.name}</option>)}
                          </select>
                          <label className="checkbox-group">
                            <input type="checkbox" checked={npc.secret} onChange={e => updateNpc(idx, { secret: e.target.checked })} />
                            Secret
                          </label>
                        </div>
                        <textarea value={npc.description} rows={2} onChange={e => updateNpc(idx, { description: e.target.value })}
                          placeholder="Description..." />
                        <textarea value={npc.knowledge} rows={2} onChange={e => updateNpc(idx, { knowledge: e.target.value })}
                          placeholder="What this NPC knows..." />
                      </div>
                    </div>
                  )
                })}

                <button className="btn-add" onClick={() => setNpcs(prev => [...prev, emptyNpc()])}>
                  + Add NPC
                </button>
              </div>
            )}
          </div>
        )}

        {/* ---- Clues ---- */}
        {isEditMode && (
          <div className="collapsible-section">
            <button className="section-toggle" onClick={() => setCluesOpen(!cluesOpen)}>
              <span className="toggle-icon">{cluesOpen ? '▾' : '▸'}</span>
              Clues ({clues.filter(c => !c._destroy).length})
            </button>

            {cluesOpen && (
              <div className="section-body">
                <p className="section-hint">
                  Discoverable pieces of information. Link to NPCs, locations, and prerequisite clues for gated reveals.
                </p>

                {clues.filter(c => !c._destroy).length === 0 && (
                  <p className="empty-hint">No clues yet. Use "Enrich Story" or add manually.</p>
                )}

                {clues.map((clue, idx) => {
                  if (clue._destroy) return null
                  const isAi = clue.source === 'enricher' || clue.source === 'embellisher'
                  return (
                    <div key={clue.id || `clue-${idx}`} className={`nested-card ${isAi ? 'ai-sourced' : ''}`}>
                      <div className="nested-card-header">
                        {isAi && <span className="source-badge">{clue.source}</span>}
                        <input type="text" className="inline-name" value={clue.title}
                          onChange={e => updateClue(idx, { title: e.target.value })}
                          placeholder="Clue title" />
                        <select className="compact-select" value={clue.discovery_method}
                          onChange={e => updateClue(idx, { discovery_method: e.target.value as DiscoveryMethod })}>
                          {DISCOVERY_METHODS.map(m => <option key={m} value={m}>{m}</option>)}
                        </select>
                        <select className="compact-select" value={clue.difficulty}
                          onChange={e => updateClue(idx, { difficulty: e.target.value as ClueDifficulty })}>
                          {CLUE_DIFFICULTIES.map(d => <option key={d} value={d}>{d}</option>)}
                        </select>
                        <button className="btn-remove" onClick={() => removeClue(idx)}>&#x2715;</button>
                      </div>
                      <div className="nested-card-body">
                        <div className="inline-row">
                          <select value={clue.location_id || ''} onChange={e => updateClue(idx, { location_id: Number(e.target.value) || null })}>
                            <option value="">-- location --</option>
                            {savedLocations.map(sl => <option key={sl.id} value={sl.id}>{sl.name}</option>)}
                          </select>
                          <select value={clue.npc_id || ''} onChange={e => updateClue(idx, { npc_id: Number(e.target.value) || null })}>
                            <option value="">-- NPC --</option>
                            {savedNpcs.map(n => <option key={n.id} value={n.id}>{n.name}</option>)}
                          </select>
                        </div>
                        <textarea value={clue.description} rows={2} onChange={e => updateClue(idx, { description: e.target.value })}
                          placeholder="Clue description..." />
                        <textarea value={clue.reveals_secret} rows={2} onChange={e => updateClue(idx, { reveals_secret: e.target.value })}
                          placeholder="What secret does this reveal?..." />
                        {savedClues.filter(sc => sc.id !== clue.id).length > 0 && (
                          <div className="relation-picker">
                            <label className="relation-label">Prerequisite clues</label>
                            <div className="relation-chips">
                              {savedClues.filter(sc => sc.id !== clue.id).map(sc => {
                                const selected = (clue.prerequisite_clue_ids || []).includes(sc.id!)
                                return (
                                  <button key={sc.id} type="button"
                                    className={`relation-chip ${selected ? 'selected' : ''}`}
                                    onClick={() => {
                                      const ids = clue.prerequisite_clue_ids || []
                                      updateClue(idx, {
                                        prerequisite_clue_ids: selected
                                          ? ids.filter(id => id !== sc.id)
                                          : [...ids, sc.id!],
                                      })
                                    }}>
                                    {sc.title || '(untitled)'}
                                  </button>
                                )
                              })}
                            </div>
                          </div>
                        )}
                      </div>
                    </div>
                  )
                })}

                <button className="btn-add" onClick={() => setClues(prev => [...prev, emptyClue()])}>
                  + Add Clue
                </button>
              </div>
            )}
          </div>
        )}

        {/* ---- Milestones ---- */}
        {isEditMode && (
          <div className="collapsible-section">
            <button className="section-toggle" onClick={() => setMilestonesOpen(!milestonesOpen)}>
              <span className="toggle-icon">{milestonesOpen ? '▾' : '▸'}</span>
              Milestones ({milestones.filter(m => !m._destroy).length})
            </button>

            {milestonesOpen && (
              <div className="section-body">
                <p className="section-hint">
                  Major plot events triggered when specific clues are discovered. Define trigger clues and consequences.
                </p>

                {milestones.filter(m => !m._destroy).length === 0 && (
                  <p className="empty-hint">No milestones yet. Use "Enrich Story" or add manually.</p>
                )}

                {milestones.map((ms, idx) => {
                  if (ms._destroy) return null
                  const isAi = ms.source === 'enricher'
                  return (
                    <div key={ms.id || `ms-${idx}`} className={`nested-card ${isAi ? 'ai-sourced' : ''}`}>
                      <div className="nested-card-header">
                        {isAi && <span className="source-badge">{ms.source}</span>}
                        <input type="text" className="inline-name" value={ms.title}
                          onChange={e => updateMilestone(idx, { title: e.target.value })}
                          placeholder="Milestone title" />
                        <button className="btn-remove" onClick={() => removeMilestone(idx)}>&#x2715;</button>
                      </div>
                      <div className="nested-card-body">
                        <textarea value={ms.description} rows={2} onChange={e => updateMilestone(idx, { description: e.target.value })}
                          placeholder="Milestone description..." />
                        <textarea value={ms.consequence} rows={2} onChange={e => updateMilestone(idx, { consequence: e.target.value })}
                          placeholder="What happens when this milestone is reached?..." />
                        {savedClues.length > 0 && (
                          <div className="relation-picker">
                            <label className="relation-label">Trigger clues</label>
                            <div className="relation-chips">
                              {savedClues.map(sc => {
                                const selected = (ms.trigger_clue_ids || []).includes(sc.id!)
                                return (
                                  <button key={sc.id} type="button"
                                    className={`relation-chip ${selected ? 'selected' : ''}`}
                                    onClick={() => {
                                      const ids = ms.trigger_clue_ids || []
                                      updateMilestone(idx, {
                                        trigger_clue_ids: selected
                                          ? ids.filter(id => id !== sc.id)
                                          : [...ids, sc.id!],
                                      })
                                    }}>
                                    {sc.title || '(untitled)'}
                                  </button>
                                )
                              })}
                            </div>
                          </div>
                        )}
                      </div>
                    </div>
                  )
                })}

                <button className="btn-add" onClick={() => setMilestones(prev => [...prev, emptyMilestone()])}>
                  + Add Milestone
                </button>
              </div>
            )}
          </div>
        )}

        <div className="editor-actions">
          <button className="btn-save" onClick={saveStory} disabled={saving || !canSave}>
            {saving ? 'Saving...' : isNew ? 'Create Story' : 'Save Changes'}
          </button>
        </div>
      </div>
    </div>
  )
}

export default AdminStoryEditor
