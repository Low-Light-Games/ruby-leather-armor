import type {
  StoryLocationData,
  EncounterTableData, EncounterTableEntryData,
  StoryNpcData,
  BestiaryEntryData,
  NpcRole, NpcAttitude,
} from '../../types'

export type { NpcRole, NpcAttitude }
export type {
  StoryLocationData,
  EncounterTableData, EncounterTableEntryData,
  StoryNpcData,
  BestiaryEntryData,
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
  story_locations?: StoryLocationData[]
  encounter_tables?: EncounterTableData[]
  story_npcs?: StoryNpcData[]
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
