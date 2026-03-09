import { useState, useEffect, useCallback, useRef } from 'react'
import { useAuth } from '../../contexts/AuthContext'
import AdminNavbar from '../AdminNavbar/AdminNavbar'
import Login from '../Login'
import FlashMessage from '../FlashMessage'
import { apiFetch } from '../../utils/api'
import type {
  StoryLocationData, LocationConnectionData,
  EncounterTableData, EncounterTableEntryData, CreatureManifestEntry,
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
  initial_contexts?: InitialContexts
  story_locations?: StoryLocationData[]
  encounter_tables?: EncounterTableData[]
  story_npcs?: StoryNpcData[]
  story_clues?: StoryClueData[]
  story_milestones?: StoryMilestoneData[]
}

// ---- Initial Contexts types ----

interface TraversalCtx {
  current_location: string
  destination: string
  terrain: string
  weather: string
  time_of_day: string
  exits: string[]
  nearby_npcs: string[]
  points_of_interest: string[]
}

interface CombatCtx {
  active: boolean
  round: number | null
  terrain_notes: string
}

interface SocialNpcPresent {
  name: string
  role: string
  attitude: 'friendly' | 'indifferent' | 'unfriendly'
  notes: string
}

interface SocialCtx {
  scene: string
  conversation_state: string
  stakes: string
  npcs_present: SocialNpcPresent[]
}

interface ExplorationCtx {
  searched_areas: string[]
  discovered_items: string[]
  discovered_secrets: string[]
  active_detection: string
  pending_investigations: string[]
}

interface RestCtx {
  resting: boolean
  hours_completed: number | null
  total_hours_needed: number | null
  rest_complete: boolean
  hp_recovered: number | null
}

interface InventoryCtx {
  recently_acquired: string[]
  notable_consumables_remaining: string[]
  equipped_changes: string[]
}

interface InitialContexts {
  traversal_context?: Partial<TraversalCtx>
  combat_context?: Partial<CombatCtx>
  social_context?: Partial<SocialCtx>
  exploration_context?: Partial<ExplorationCtx>
  rest_context?: Partial<RestCtx>
  inventory_context?: Partial<InventoryCtx>
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

const emptyTraversalCtx = (): TraversalCtx => ({
  current_location: '', destination: '', terrain: '', weather: '', time_of_day: '',
  exits: [], nearby_npcs: [], points_of_interest: [],
})

const emptyCombatCtx = (): CombatCtx => ({
  active: false, round: null, terrain_notes: '',
})

const emptySocialNpc = (): SocialNpcPresent => ({
  name: '', role: '', attitude: 'indifferent', notes: '',
})

const emptySocialCtx = (): SocialCtx => ({
  scene: '', conversation_state: '', stakes: '', npcs_present: [],
})

const emptyExplorationCtx = (): ExplorationCtx => ({
  searched_areas: [], discovered_items: [], discovered_secrets: [],
  active_detection: '', pending_investigations: [],
})

const emptyRestCtx = (): RestCtx => ({
  resting: false, hours_completed: null, total_hours_needed: null,
  rest_complete: false, hp_recovered: null,
})

const emptyInventoryCtx = (): InventoryCtx => ({
  recently_acquired: [], notable_consumables_remaining: [], equipped_changes: [],
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
    hydrateInitialContexts(data.initial_contexts || {})
  }

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

  const buildInitialContextsPayload = (): InitialContexts => {
    const strip = (obj: Record<string, unknown>): Record<string, unknown> | null => {
      const clean: Record<string, unknown> = {}
      for (const [k, v] of Object.entries(obj)) {
        if (v === '' || v === null || v === undefined) continue
        if (Array.isArray(v) && v.length === 0) continue
        if (typeof v === 'boolean' && !v) continue
        clean[k] = v
      }
      return Object.keys(clean).length > 0 ? clean : null
    }

    const ic: Record<string, unknown> = {}
    const t = strip(icTraversal as unknown as Record<string, unknown>)
    if (t) ic.traversal_context = t
    const c = strip(icCombat as unknown as Record<string, unknown>)
    if (c) ic.combat_context = c
    const s = strip({ ...icSocial, npcs_present: icSocial.npcs_present.length > 0 ? icSocial.npcs_present : undefined } as unknown as Record<string, unknown>)
    if (s) ic.social_context = s
    const e = strip(icExploration as unknown as Record<string, unknown>)
    if (e) ic.exploration_context = e
    const r = strip(icRest as unknown as Record<string, unknown>)
    if (r) ic.rest_context = r
    const inv = strip(icInventory as unknown as Record<string, unknown>)
    if (inv) ic.inventory_context = inv
    return ic as InitialContexts
  }

  const buildPayload = (skipUnresolvedConns = false) => {
    const story: Record<string, unknown> = {
      title, preview, premise, hook,
      initial_context: initialContext,
      initial_summary: initialSummary,
      initial_contexts: buildInitialContextsPayload(),
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

      // Apply encounter manifests to matching entries
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

      // Apply proposed encounter tables
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
          <label htmlFor="story-title" title="The story's display name, shown in the adventure picker and admin list.">Title</label>
          <input type="text" id="story-title" value={title}
            onChange={e => setTitle(e.target.value)} placeholder="The Goblin Caves, Shadow over Millhaven, ..." />
        </div>

        <div className="form-field">
          <label htmlFor="story-preview" title="A short teaser the player sees before starting the adventure. No spoilers.">Preview (shown to players)</label>
          <textarea id="story-preview" value={preview}
            onChange={e => setPreview(e.target.value)} rows={3}
            placeholder="1-2 sentences the player reads before choosing this story. Set the tone without revealing the plot." />
        </div>

        <div className="form-field">
          <label htmlFor="story-premise" title="The full plot, secrets, and villain motivations. Only the AI sees this — never shown to the player. The Enricher uses this to generate NPCs, clues, and milestones.">Premise (full story, admin only)</label>
          <textarea id="story-premise" value={premise}
            onChange={e => setPremise(e.target.value)} rows={6}
            placeholder="The complete plot with all secrets and twists. Who is the villain? What's really going on? Include NPC motivations, hidden connections, and the intended resolution. The AI DM reads this to run the story — the player never sees it." />
        </div>

        <div className="form-field">
          <label htmlFor="story-hook" title="A spoiler-free introduction the narrator can reference. Sets the scene without revealing secrets. Used by the Narrate step as story context.">Hook (spoiler-free narrator intro)</label>
          <textarea id="story-hook" value={hook}
            onChange={e => setHook(e.target.value)} rows={4}
            placeholder="A narrator-safe description of the setting and situation. The narrator sees this instead of the premise to avoid spoiling secrets. E.g. 'Rumors of goblin raids have reached the village. The mayor is looking for adventurers.'" />
        </div>

        <div className="form-field">
          <label htmlFor="story-initial-context" title="The first DM message the player sees. This is sent as a narrative message when the adventure starts. Describe where the player wakes up or arrives.">Initial Context (opening DM message)</label>
          <textarea id="story-initial-context" value={initialContext}
            onChange={e => setInitialContext(e.target.value)} rows={4}
            placeholder="The opening narration. E.g. 'You wake in a small bedroom at the Village Inn. Sunlight streams through a window. Downstairs, you hear the murmur of the morning crowd.' This is the first thing the player reads." />
        </div>

        <div className="form-field">
          <label htmlFor="story-initial-summary" title="Seeds the 'story so far' field that the narrator and other steps use for context. Should reflect the starting state, not the plot.">Initial Summary (story-so-far seed)</label>
          <textarea id="story-initial-summary" value={initialSummary}
            onChange={e => setInitialSummary(e.target.value)} rows={4}
            placeholder="A brief status line from the player's perspective. E.g. 'Just arrived at the village after hearing rumors of goblin trouble. No leads yet.' This seeds the macro narrative tracker." />
        </div>

        {/* ---- Enrich Story button ---- */}
        {isEditMode && (
          <div className="enrich-section">
            <button className="btn-enrich" onClick={enrichStory} disabled={enriching || !premise.trim()}
              title="Uses AI to extract NPCs, clues, milestones, encounter data, and initial contexts from the premise. Results appear below for review — nothing is saved until you click Save.">
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
                                  <label className="entry-description-label" title="Optional. For Fixed: text shown when this entry is rolled. For AI: hint used to generate the scene. Can be left blank if the creature manifest is enough.">
                                    Description (optional)
                                  </label>
                                  <textarea value={entry.description} rows={2}
                                    onChange={e => updateEntry(tableIdx, entryIdx, { description: e.target.value })}
                                    placeholder={entry.entry_type === 'fixed'
                                      ? 'Fixed: text shown when this entry is rolled. Leave blank if manifest is enough.'
                                      : 'AI: hint for scene generation. Leave blank for generic encounter.'} />

                                  {/* Creature Manifest */}
                                  <div className="manifest-section">
                                    <div className="manifest-header">
                                      <strong>Creatures ({(entry.creature_manifest || []).length})</strong>
                                      <button className="btn-add-sm" onClick={() => {
                                        const manifest = [...(entry.creature_manifest || []), { bestiary_entry_id: null, count: 1, display_name: '' }]
                                        updateEntry(tableIdx, entryIdx, { creature_manifest: manifest })
                                      }}>+ Creature</button>
                                    </div>
                                    {(entry.creature_manifest || []).map((c: CreatureManifestEntry, cIdx: number) => (
                                      <div key={cIdx} className="manifest-row">
                                        <input type="text" className="manifest-name" value={c.display_name}
                                          placeholder="Display name" onChange={e => {
                                            const manifest = [...(entry.creature_manifest || [])]
                                            manifest[cIdx] = { ...manifest[cIdx], display_name: e.target.value }
                                            updateEntry(tableIdx, entryIdx, { creature_manifest: manifest })
                                          }} />
                                        <input type="text" className="manifest-bestiary" value={c.bestiary_entry_id || ''}
                                          placeholder="Bestiary ID" onChange={e => {
                                            const manifest = [...(entry.creature_manifest || [])]
                                            manifest[cIdx] = { ...manifest[cIdx], bestiary_entry_id: e.target.value || null }
                                            updateEntry(tableIdx, entryIdx, { creature_manifest: manifest })
                                          }} />
                                        <label className="manifest-count">
                                          x<input type="number" min={1} value={c.count}
                                            onChange={e => {
                                              const manifest = [...(entry.creature_manifest || [])]
                                              manifest[cIdx] = { ...manifest[cIdx], count: Number(e.target.value) || 1 }
                                              updateEntry(tableIdx, entryIdx, { creature_manifest: manifest })
                                            }} />
                                        </label>
                                        <button className="btn-remove-sm" onClick={() => {
                                          const manifest = (entry.creature_manifest || []).filter((_: any, i: number) => i !== cIdx)
                                          updateEntry(tableIdx, entryIdx, { creature_manifest: manifest })
                                        }}>&#x2715;</button>
                                      </div>
                                    ))}
                                  </div>
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

        {/* ---- Initial Contexts ---- */}
        {isEditMode && (
          <div className="collapsible-section">
            <button className="section-toggle" onClick={() => setInitialContextsOpen(!initialContextsOpen)}>
              <span className="toggle-icon">{initialContextsOpen ? '▾' : '▸'}</span>
              Initial Contexts
            </button>

            {initialContextsOpen && (
              <div className="section-body">
                <p className="section-hint">
                  Structured starting game state seeded into every new adventure. Without these, contexts start empty and the AI may misinterpret missing data as negative facts (e.g. no exits = trapped). Fill at least Traversal for any story. Use "Enrich Story" to auto-generate these from the premise.
                </p>

                {/* -- Traversal -- */}
                <div className="nested-card">
                  <div className="nested-card-header">
                    <button className="expand-btn" onClick={() => setIcSubOpen(p => ({ ...p, traversal: !p.traversal }))}>
                      {icSubOpen.traversal ? '▾' : '▸'}
                    </button>
                    <span className="inline-name" style={{ cursor: 'default', fontWeight: 600 }}
                      title="Where the player physically is when the adventure begins. This is the most important context to fill — it prevents the sanity checker from blocking basic movement.">Traversal</span>
                  </div>
                  {icSubOpen.traversal && (
                    <div className="nested-card-body">
                      <div className="form-field compact">
                        <label title="The specific place the player starts in. This becomes traversal_context.current_location — every AI step reads it to know where the player is.">Starting location</label>
                        <input type="text" value={icTraversal.current_location}
                          onChange={e => setIcTraversal(p => ({ ...p, current_location: e.target.value }))}
                          placeholder="Be specific: 'upstairs bedroom at the Village Inn', not just 'Village Inn'" />
                      </div>
                      <div className="form-field compact">
                        <label title="Only set this if the story begins mid-journey. Leave empty if the player starts stationary.">Destination (if mid-travel)</label>
                        <input type="text" value={icTraversal.destination}
                          onChange={e => setIcTraversal(p => ({ ...p, destination: e.target.value }))}
                          placeholder="Leave empty unless the player starts already traveling somewhere" />
                      </div>
                      <div className="form-field compact">
                        <label title="The type of ground/environment. Used by the narrator for descriptions and by mechanics for terrain-dependent checks.">Terrain type</label>
                        <input type="text" value={icTraversal.terrain}
                          onChange={e => setIcTraversal(p => ({ ...p, terrain: e.target.value }))}
                          placeholder="indoor wooden floor, outdoor dirt road, forest undergrowth, cave stone, ..." />
                      </div>
                      <div className="form-field compact">
                        <label title="Current weather at the start. Affects narrator prose and some mechanics (e.g. perception penalties in rain).">Weather</label>
                        <input type="text" value={icTraversal.weather}
                          onChange={e => setIcTraversal(p => ({ ...p, weather: e.target.value }))}
                          placeholder="clear skies, light rain, heavy fog, snowfall, ..." />
                      </div>
                      <div className="form-field compact">
                        <label title="General time description. The exact hour comes from the time_context system, but this helps the narrator set the mood.">Time of day</label>
                        <input type="text" value={icTraversal.time_of_day}
                          onChange={e => setIcTraversal(p => ({ ...p, time_of_day: e.target.value }))}
                          placeholder="early morning, midday, late afternoon, dusk, midnight, ..." />
                      </div>
                      <div className="form-field compact">
                        <label title="Ways out of the starting location. CRITICAL: if left empty, the sanity checker may block the player from leaving. List every obvious exit — doors, windows, paths, staircases.">Known exits</label>
                        <div className="tag-list">
                          {icTraversal.exits.map((ex, i) => (
                            <div key={i} className="tag-item">
                              <input type="text" value={ex}
                                onChange={e => setIcTraversal(p => ({ ...p, exits: p.exits.map((v, j) => j === i ? e.target.value : v) }))}
                                placeholder="door to hallway, window overlooking the street, staircase down, ..." />
                              <button className="btn-remove-sm" onClick={() => setIcTraversal(p => ({ ...p, exits: p.exits.filter((_, j) => j !== i) }))}>&#x2715;</button>
                            </div>
                          ))}
                          <button className="btn-add-sm" onClick={() => setIcTraversal(p => ({ ...p, exits: [...p.exits, ''] }))}>+ Add exit</button>
                        </div>
                      </div>
                      <div className="form-field compact">
                        <label title="NPCs visibly present at the starting location. Must match NPC names from the NPCs section.">Nearby NPCs</label>
                        <div className="tag-list">
                          {icTraversal.nearby_npcs.map((npc, i) => (
                            <div key={i} className="tag-item">
                              <input type="text" value={npc}
                                onChange={e => setIcTraversal(p => ({ ...p, nearby_npcs: p.nearby_npcs.map((v, j) => j === i ? e.target.value : v) }))}
                                placeholder="Must match an NPC name from the NPCs section" />
                              <button className="btn-remove-sm" onClick={() => setIcTraversal(p => ({ ...p, nearby_npcs: p.nearby_npcs.filter((_, j) => j !== i) }))}>&#x2715;</button>
                            </div>
                          ))}
                          <button className="btn-add-sm" onClick={() => setIcTraversal(p => ({ ...p, nearby_npcs: [...p.nearby_npcs, ''] }))}>+ Add NPC</button>
                        </div>
                      </div>
                      <div className="form-field compact">
                        <label title="Notable objects or features the player can see or interact with at the starting location.">Points of interest</label>
                        <div className="tag-list">
                          {icTraversal.points_of_interest.map((poi, i) => (
                            <div key={i} className="tag-item">
                              <input type="text" value={poi}
                                onChange={e => setIcTraversal(p => ({ ...p, points_of_interest: p.points_of_interest.map((v, j) => j === i ? e.target.value : v) }))}
                                placeholder="a notice board, a locked chest, a campfire, an old well, ..." />
                              <button className="btn-remove-sm" onClick={() => setIcTraversal(p => ({ ...p, points_of_interest: p.points_of_interest.filter((_, j) => j !== i) }))}>&#x2715;</button>
                            </div>
                          ))}
                          <button className="btn-add-sm" onClick={() => setIcTraversal(p => ({ ...p, points_of_interest: [...p.points_of_interest, ''] }))}>+ Add point</button>
                        </div>
                      </div>
                    </div>
                  )}
                </div>

                {/* -- Combat -- */}
                <div className="nested-card">
                  <div className="nested-card-header">
                    <button className="expand-btn" onClick={() => setIcSubOpen(p => ({ ...p, combat: !p.combat }))}>
                      {icSubOpen.combat ? '▾' : '▸'}
                    </button>
                    <span className="inline-name" style={{ cursor: 'default', fontWeight: 600 }}
                      title="Only fill this if the story begins mid-combat (e.g. an ambush as the opening scene). Most stories leave this empty.">Combat</span>
                  </div>
                  {icSubOpen.combat && (
                    <div className="nested-card-body">
                      <label className="checkbox-group" title="When checked, the pipeline treats the first player input as a combat action.">
                        <input type="checkbox" checked={icCombat.active}
                          onChange={e => setIcCombat(p => ({ ...p, active: e.target.checked }))} />
                        Combat active at start
                      </label>
                      {icCombat.active && (
                        <p className="section-hint">The player will be in initiative order from turn one. Encounter participants come from the story's encounter tables — make sure those are set up.</p>
                      )}
                      <div className="form-field compact">
                        <label title="Which round of combat the fight starts in. Usually 1 unless you're dropping the player into an already ongoing battle.">Starting round</label>
                        <input type="number" value={icCombat.round ?? ''} min={1}
                          onChange={e => setIcCombat(p => ({ ...p, round: e.target.value ? Number(e.target.value) : null }))}
                          placeholder="1" />
                      </div>
                      <div className="form-field compact">
                        <label title="Describes the battlefield. The narrator uses this for combat descriptions. Pathfinder terrain keywords (difficult terrain, cover, elevation) are most useful.">Terrain / battlefield notes</label>
                        <input type="text" value={icCombat.terrain_notes}
                          onChange={e => setIcCombat(p => ({ ...p, terrain_notes: e.target.value }))}
                          placeholder="narrow corridor with difficult terrain, open field with scattered boulders for cover, ..." />
                      </div>
                    </div>
                  )}
                </div>

                {/* -- Social -- */}
                <div className="nested-card">
                  <div className="nested-card-header">
                    <button className="expand-btn" onClick={() => setIcSubOpen(p => ({ ...p, social: !p.social }))}>
                      {icSubOpen.social ? '▾' : '▸'}
                    </button>
                    <span className="inline-name" style={{ cursor: 'default', fontWeight: 600 }}
                      title="Fill this if the adventure opens with an ongoing conversation or social encounter. Otherwise leave empty — it will populate naturally during play.">Social</span>
                  </div>
                  {icSubOpen.social && (
                    <div className="nested-card-body">
                      <div className="form-field compact">
                        <label title="Brief summary of what's happening socially when the adventure starts. The chronicler uses this to track conversation progression.">Scene description</label>
                        <input type="text" value={icSocial.scene}
                          onChange={e => setIcSocial(p => ({ ...p, scene: e.target.value }))}
                          placeholder="The innkeeper is chatting with a hooded stranger at the bar; a merchant argues with a guard at the door" />
                      </div>
                      <div className="form-field compact">
                        <label title="Where in the conversation things stand. Helps the AI know whether to have NPCs introduce themselves or continue an ongoing exchange.">Conversation state</label>
                        <input type="text" value={icSocial.conversation_state}
                          onChange={e => setIcSocial(p => ({ ...p, conversation_state: e.target.value }))}
                          placeholder="not yet started, introductions, mid-negotiation, heated argument, ..." />
                      </div>
                      <div className="form-field compact">
                        <label title="What's at risk in this social encounter. Guides the AI in setting DCs and consequences for Diplomacy/Intimidate/Bluff checks.">Stakes</label>
                        <input type="text" value={icSocial.stakes}
                          onChange={e => setIcSocial(p => ({ ...p, stakes: e.target.value }))}
                          placeholder="Gaining the elder's trust, buying supplies at a fair price, getting directions to the ruins, ..." />
                      </div>
                      <div className="form-field compact">
                        <label title="NPCs the player can interact with right now. Names should match the NPC records you defined above. Attitude influences initial Diplomacy DCs.">NPCs in the social scene</label>
                        {icSocial.npcs_present.map((npc, i) => (
                          <div key={i} className="connection-row">
                            <input type="text" value={npc.name} placeholder="NPC name (match NPCs section)"
                              onChange={e => setIcSocial(p => ({ ...p, npcs_present: p.npcs_present.map((n, j) => j === i ? { ...n, name: e.target.value } : n) }))} />
                            <input type="text" value={npc.role} placeholder="Role: innkeeper, guard, merchant, ..."
                              onChange={e => setIcSocial(p => ({ ...p, npcs_present: p.npcs_present.map((n, j) => j === i ? { ...n, role: e.target.value } : n) }))} />
                            <select value={npc.attitude} title="Starting attitude toward the player (Pathfinder Diplomacy scale)"
                              onChange={e => setIcSocial(p => ({ ...p, npcs_present: p.npcs_present.map((n, j) => j === i ? { ...n, attitude: e.target.value as SocialNpcPresent['attitude'] } : n) }))}>
                              <option value="friendly">friendly</option>
                              <option value="indifferent">indifferent</option>
                              <option value="unfriendly">unfriendly</option>
                            </select>
                            <input type="text" value={npc.notes} placeholder="Extra detail: nervous, hiding something, will offer a quest, ..."
                              onChange={e => setIcSocial(p => ({ ...p, npcs_present: p.npcs_present.map((n, j) => j === i ? { ...n, notes: e.target.value } : n) }))} />
                            <button className="btn-remove-sm" onClick={() => setIcSocial(p => ({ ...p, npcs_present: p.npcs_present.filter((_, j) => j !== i) }))}>&#x2715;</button>
                          </div>
                        ))}
                        <button className="btn-add-sm" onClick={() => setIcSocial(p => ({ ...p, npcs_present: [...p.npcs_present, emptySocialNpc()] }))}>+ Add NPC</button>
                      </div>
                    </div>
                  )}
                </div>

                {/* -- Exploration -- */}
                <div className="nested-card">
                  <div className="nested-card-header">
                    <button className="expand-btn" onClick={() => setIcSubOpen(p => ({ ...p, exploration: !p.exploration }))}>
                      {icSubOpen.exploration ? '▾' : '▸'}
                    </button>
                    <span className="inline-name" style={{ cursor: 'default', fontWeight: 600 }}
                      title="Pre-seeded exploration state. Usually empty for new stories. Fill if the player should already know about certain items, secrets, or searched areas before play begins.">Exploration</span>
                  </div>
                  {icSubOpen.exploration && (
                    <div className="nested-card-body">
                      <div className="form-field compact">
                        <label title="A detection spell or ability already active when the adventure starts (e.g. Detect Magic). Leave empty if none.">Active detection</label>
                        <input type="text" value={icExploration.active_detection}
                          onChange={e => setIcExploration(p => ({ ...p, active_detection: e.target.value }))}
                          placeholder="Detect Magic, Detect Evil, ... (usually empty)" />
                      </div>
                      <div className="form-field compact">
                        <label title="Areas the player has already searched before the adventure begins. Items here won't trigger new Perception checks.">Already searched areas</label>
                        <div className="tag-list">
                          {icExploration.searched_areas.map((a, i) => (
                            <div key={i} className="tag-item">
                              <input type="text" value={a}
                                onChange={e => setIcExploration(p => ({ ...p, searched_areas: p.searched_areas.map((v, j) => j === i ? e.target.value : v) }))}
                                placeholder="the bedroom nightstand, the front porch, ..." />
                              <button className="btn-remove-sm" onClick={() => setIcExploration(p => ({ ...p, searched_areas: p.searched_areas.filter((_, j) => j !== i) }))}>&#x2715;</button>
                            </div>
                          ))}
                          <button className="btn-add-sm" onClick={() => setIcExploration(p => ({ ...p, searched_areas: [...p.searched_areas, ''] }))}>+ Add area</button>
                        </div>
                      </div>
                      <div className="form-field compact">
                        <label title="Items the player already found or has knowledge of. These show up as known in the exploration tracker.">Already discovered items</label>
                        <div className="tag-list">
                          {icExploration.discovered_items.map((item, i) => (
                            <div key={i} className="tag-item">
                              <input type="text" value={item}
                                onChange={e => setIcExploration(p => ({ ...p, discovered_items: p.discovered_items.map((v, j) => j === i ? e.target.value : v) }))}
                                placeholder="a tattered journal, a rusted key, ..." />
                              <button className="btn-remove-sm" onClick={() => setIcExploration(p => ({ ...p, discovered_items: p.discovered_items.filter((_, j) => j !== i) }))}>&#x2715;</button>
                            </div>
                          ))}
                          <button className="btn-add-sm" onClick={() => setIcExploration(p => ({ ...p, discovered_items: [...p.discovered_items, ''] }))}>+ Add item</button>
                        </div>
                      </div>
                      <div className="form-field compact">
                        <label title="Hidden information the player already knows going in. Rare — only use for stories that pick up after a prior event.">Already discovered secrets</label>
                        <div className="tag-list">
                          {icExploration.discovered_secrets.map((s, i) => (
                            <div key={i} className="tag-item">
                              <input type="text" value={s}
                                onChange={e => setIcExploration(p => ({ ...p, discovered_secrets: p.discovered_secrets.map((v, j) => j === i ? e.target.value : v) }))}
                                placeholder="the innkeeper works for the bandits, the well leads to underground tunnels, ..." />
                              <button className="btn-remove-sm" onClick={() => setIcExploration(p => ({ ...p, discovered_secrets: p.discovered_secrets.filter((_, j) => j !== i) }))}>&#x2715;</button>
                            </div>
                          ))}
                          <button className="btn-add-sm" onClick={() => setIcExploration(p => ({ ...p, discovered_secrets: [...p.discovered_secrets, ''] }))}>+ Add secret</button>
                        </div>
                      </div>
                      <div className="form-field compact">
                        <label title="Open threads the player is aware of but hasn't resolved yet. These appear in the exploration tracker as active leads.">Pending investigations</label>
                        <div className="tag-list">
                          {icExploration.pending_investigations.map((inv, i) => (
                            <div key={i} className="tag-item">
                              <input type="text" value={inv}
                                onChange={e => setIcExploration(p => ({ ...p, pending_investigations: p.pending_investigations.map((v, j) => j === i ? e.target.value : v) }))}
                                placeholder="strange noises from the cellar, the missing merchant's last known route, ..." />
                              <button className="btn-remove-sm" onClick={() => setIcExploration(p => ({ ...p, pending_investigations: p.pending_investigations.filter((_, j) => j !== i) }))}>&#x2715;</button>
                            </div>
                          ))}
                          <button className="btn-add-sm" onClick={() => setIcExploration(p => ({ ...p, pending_investigations: [...p.pending_investigations, ''] }))}>+ Add investigation</button>
                        </div>
                      </div>
                    </div>
                  )}
                </div>

                {/* -- Rest -- */}
                <div className="nested-card">
                  <div className="nested-card-header">
                    <button className="expand-btn" onClick={() => setIcSubOpen(p => ({ ...p, rest: !p.rest }))}>
                      {icSubOpen.rest ? '▾' : '▸'}
                    </button>
                    <span className="inline-name" style={{ cursor: 'default', fontWeight: 600 }}
                      title="Only fill this if the story opens while the player is mid-rest (e.g. woken by an ambush during a long rest). Almost always left empty.">Rest</span>
                  </div>
                  {icSubOpen.rest && (
                    <div className="nested-card-body">
                      <label className="checkbox-group" title="Check if the player is currently in a long rest when the adventure begins. This blocks spell recovery and affects how interruptions are handled.">
                        <input type="checkbox" checked={icRest.resting}
                          onChange={e => setIcRest(p => ({ ...p, resting: e.target.checked }))} />
                        Currently resting
                      </label>
                      <label className="checkbox-group" title="Check if the rest has already finished and the player simply hasn't acted yet. Enables spell/HP recovery processing on the first turn.">
                        <input type="checkbox" checked={icRest.rest_complete}
                          onChange={e => setIcRest(p => ({ ...p, rest_complete: e.target.checked }))} />
                        Rest complete
                      </label>
                      <div className="form-field compact">
                        <label title="How many hours of the rest have elapsed so far. E.g. if woken 4 hours into an 8-hour rest, set to 4.">Hours completed</label>
                        <input type="number" value={icRest.hours_completed ?? ''} min={0}
                          onChange={e => setIcRest(p => ({ ...p, hours_completed: e.target.value ? Number(e.target.value) : null }))}
                          placeholder="0" />
                      </div>
                      <div className="form-field compact">
                        <label title="Total hours needed for a full rest. Standard Pathfinder long rest is 8 hours.">Total hours needed</label>
                        <input type="number" value={icRest.total_hours_needed ?? ''} min={0}
                          onChange={e => setIcRest(p => ({ ...p, total_hours_needed: e.target.value ? Number(e.target.value) : null }))}
                          placeholder="8" />
                      </div>
                      <div className="form-field compact">
                        <label title="HP already recovered before the adventure starts. Usually 0 unless the story picks up after a partial rest.">HP recovered so far</label>
                        <input type="number" value={icRest.hp_recovered ?? ''} min={0}
                          onChange={e => setIcRest(p => ({ ...p, hp_recovered: e.target.value ? Number(e.target.value) : null }))}
                          placeholder="0" />
                      </div>
                    </div>
                  )}
                </div>

                {/* -- Inventory -- */}
                <div className="nested-card">
                  <div className="nested-card-header">
                    <button className="expand-btn" onClick={() => setIcSubOpen(p => ({ ...p, inventory: !p.inventory }))}>
                      {icSubOpen.inventory ? '▾' : '▸'}
                    </button>
                    <span className="inline-name" style={{ cursor: 'default', fontWeight: 600 }}
                      title="Tracks notable inventory changes between turns. Almost always empty at story start — the character sheet holds the full inventory. Only fill if the story gives the player a special item right away.">Inventory</span>
                  </div>
                  {icSubOpen.inventory && (
                    <div className="nested-card-body">
                      <div className="form-field compact">
                        <label title="Items the player has just received or found. These are highlighted in the inventory tracker as new acquisitions.">Recently acquired items</label>
                        <div className="tag-list">
                          {icInventory.recently_acquired.map((item, i) => (
                            <div key={i} className="tag-item">
                              <input type="text" value={item}
                                onChange={e => setIcInventory(p => ({ ...p, recently_acquired: p.recently_acquired.map((v, j) => j === i ? e.target.value : v) }))}
                                placeholder="a sealed letter from the mayor, a healing potion, ..." />
                              <button className="btn-remove-sm" onClick={() => setIcInventory(p => ({ ...p, recently_acquired: p.recently_acquired.filter((_, j) => j !== i) }))}>&#x2715;</button>
                            </div>
                          ))}
                          <button className="btn-add-sm" onClick={() => setIcInventory(p => ({ ...p, recently_acquired: [...p.recently_acquired, ''] }))}>+ Add item</button>
                        </div>
                      </div>
                      <div className="form-field compact">
                        <label title="Limited-use items the player has on hand (potions, scrolls, wands with charges). The pipeline uses this to validate consumable usage.">Notable consumables on hand</label>
                        <div className="tag-list">
                          {icInventory.notable_consumables_remaining.map((c, i) => (
                            <div key={i} className="tag-item">
                              <input type="text" value={c}
                                onChange={e => setIcInventory(p => ({ ...p, notable_consumables_remaining: p.notable_consumables_remaining.map((v, j) => j === i ? e.target.value : v) }))}
                                placeholder="Potion of Cure Light Wounds, Scroll of Identify, 3 torches, ..." />
                              <button className="btn-remove-sm" onClick={() => setIcInventory(p => ({ ...p, notable_consumables_remaining: p.notable_consumables_remaining.filter((_, j) => j !== i) }))}>&#x2715;</button>
                            </div>
                          ))}
                          <button className="btn-add-sm" onClick={() => setIcInventory(p => ({ ...p, notable_consumables_remaining: [...p.notable_consumables_remaining, ''] }))}>+ Add consumable</button>
                        </div>
                      </div>
                      <div className="form-field compact">
                        <label title="Equipment the player has equipped differently from their character sheet defaults. E.g. if the story starts with armor removed.">Equipment overrides</label>
                        <div className="tag-list">
                          {icInventory.equipped_changes.map((eq, i) => (
                            <div key={i} className="tag-item">
                              <input type="text" value={eq}
                                onChange={e => setIcInventory(p => ({ ...p, equipped_changes: p.equipped_changes.map((v, j) => j === i ? e.target.value : v) }))}
                                placeholder="armor removed (sleeping), wearing a disguise, borrowed longsword, ..." />
                              <button className="btn-remove-sm" onClick={() => setIcInventory(p => ({ ...p, equipped_changes: p.equipped_changes.filter((_, j) => j !== i) }))}>&#x2715;</button>
                            </div>
                          ))}
                          <button className="btn-add-sm" onClick={() => setIcInventory(p => ({ ...p, equipped_changes: [...p.equipped_changes, ''] }))}>+ Add change</button>
                        </div>
                      </div>
                    </div>
                  )}
                </div>

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
