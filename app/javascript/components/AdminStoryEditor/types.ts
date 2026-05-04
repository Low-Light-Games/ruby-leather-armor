import type {
  StoryLocationData,
  EncounterTableData, EncounterTableEntryData,
  StoryNpcData,
  NpcRole, NpcAttitude,
} from '../../types'

export type { NpcRole, NpcAttitude }
export type {
  StoryLocationData,
  EncounterTableData, EncounterTableEntryData,
  StoryNpcData,
}

// ---- Client-side identity layer for locations ----

export interface ClientLocation extends StoryLocationData {
  _clientId: string
}

// ---- Props & server data shape ----

export interface AdminStoryEditorProps {
  mode: 'create' | 'edit'
  storyId?: number
}

export interface SeedFact {
  text: string
  kind: 'event' | 'state' | 'entity'
  polarity?: 'asserts' | 'negates'
  entities?: string[]
}

export interface StoryData {
  id: number
  title: string
  preview: string
  premise: string
  opening_message?: string
  world_terrain?: string
  seed_facts?: SeedFact[]
  initial_summary: string | null
  initial_contexts?: InitialContexts
  story_locations?: StoryLocationData[]
  encounter_tables?: EncounterTableData[]
  story_npcs?: StoryNpcData[]
}

// ---- Initial Contexts types ----

export interface TraversalCtx {
  current_location: string
  destination: string
  terrain: string
  weather: string
  time_of_day: string
  exits: string[]
  nearby_npcs: string[]
  points_of_interest: string[]
}

export interface CombatCtx {
  active: boolean
  round: number | null
  terrain_notes: string
}

export interface SocialNpcPresent {
  name: string
  role: string
  attitude: 'friendly' | 'indifferent' | 'unfriendly'
  notes: string
}

export interface SocialCtx {
  scene: string
  conversation_state: string
  stakes: string
  npcs_present: SocialNpcPresent[]
}

export interface ExplorationCtx {
  searched_areas: string[]
  discovered_items: string[]
  discovered_secrets: string[]
  active_detection: string
  pending_investigations: string[]
}

export interface RestCtx {
  resting: boolean
  hours_completed: number | null
  total_hours_needed: number | null
  rest_complete: boolean
  hp_recovered: number | null
}

export interface InventoryCtx {
  recently_acquired: string[]
  notable_consumables_remaining: string[]
  equipped_changes: string[]
}

export interface InitialContexts {
  traversal_context?: Partial<TraversalCtx>
  combat_context?: Partial<CombatCtx>
  social_context?: Partial<SocialCtx>
  exploration_context?: Partial<ExplorationCtx>
  rest_context?: Partial<RestCtx>
  inventory_context?: Partial<InventoryCtx>
}

// ---- Constants ----

export const NPC_ROLES: NpcRole[] = ['quest_giver', 'informant', 'antagonist', 'bystander', 'merchant']
export const NPC_ATTITUDES: NpcAttitude[] = ['friendly', 'indifferent', 'unfriendly']

// ---- Empty constructors ----

export const emptyLocation = (): ClientLocation => ({
  name: '', description: '', starting: false,
  _clientId: crypto.randomUUID(),
})

export const emptyTable = (): EncounterTableData => ({
  name: '', description: '', check_frequency_hours: 4, encounter_chance: 15, encounter_table_entries: []
})

export const emptyEntry = (): EncounterTableEntryData => ({
  title: '', description: '', entry_type: 'fixed', weight: 1
})

export const emptyNpc = (): StoryNpcData => ({
  source: 'manual', name: '', role: 'bystander', description: '',
  knowledge: '', attitude: 'indifferent', secret: false,
})

export const emptyTraversalCtx = (): TraversalCtx => ({
  current_location: '', destination: '', terrain: '', weather: '', time_of_day: '',
  exits: [], nearby_npcs: [], points_of_interest: [],
})

export const emptyCombatCtx = (): CombatCtx => ({
  active: false, round: null, terrain_notes: '',
})

export const emptySocialNpc = (): SocialNpcPresent => ({
  name: '', role: '', attitude: 'indifferent', notes: '',
})

export const emptySocialCtx = (): SocialCtx => ({
  scene: '', conversation_state: '', stakes: '', npcs_present: [],
})

export const emptyExplorationCtx = (): ExplorationCtx => ({
  searched_areas: [], discovered_items: [], discovered_secrets: [],
  active_detection: '', pending_investigations: [],
})

export const emptyRestCtx = (): RestCtx => ({
  resting: false, hours_completed: null, total_hours_needed: null,
  rest_complete: false, hp_recovered: null,
})

export const emptyInventoryCtx = (): InventoryCtx => ({
  recently_acquired: [], notable_consumables_remaining: [], equipped_changes: [],
})

