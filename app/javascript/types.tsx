export interface SheetDetails {
  feats?: string[]          // feat IDs

  // ─── Spell storage (differentiated by casting style) ───
  /** Spontaneous casters (sorcerer, bard): their limited known spells */
  knownSpells?: string[]
  /** Wizard: spells copied into the spellbook */
  spellbook?: string[]
  /** @deprecated Legacy field — migrated to knownSpells or spellbook on load */
  spells?: string[]
}

export interface Sheet {
  id: number
  name: string
  description: string | null
  details: SheetDetails | null
  strength: number
  intelligence: number
  dexterity: number
  wisdom: number
  charisma: number
  constitution: number
  race: string | null
  racial_bonus_attribute: string | null
  character_class: string | null
  subclass: string | null
  level: number
  user_id: number
  created_at: string
  updated_at: string
}

export type AttributeType = 'strength' | 'dexterity' | 'constitution' | 'intelligence' | 'wisdom' | 'charisma';

export interface Story {
  id: number
  title: string
  preview: string
  premise: string
  created_at: string
  updated_at: string
}

export interface StoryState {
  id: number
  story_id: number
  description: string
  position: number
  created_at: string
  updated_at: string
}

export interface AdminStory {
  id: number
  title: string
  preview: string
  premise: string
  story_states: StoryState[]
  created_at: string
  updated_at: string
}

export interface AdventureSheet {
  id: number
  sheet_id: number | null
  name: string
  description: string | null
  details: SheetDetails | null
  strength: number
  intelligence: number
  dexterity: number
  constitution: number
  wisdom: number
  charisma: number
  race: string | null
  racial_bonus_attribute: string | null
  character_class: string | null
  subclass: string | null
  level: number
  gold: number
  hp: number
  max_hp: number
  items: string | null
  effects: string | null
}

export interface Adventure {
  id: number
  adventure_sheet: AdventureSheet
  story_state: StoryState
  story: Story
}

export interface AdventureSummary {
  id: number
  character_name: string
  story_title: string
  character_gold: number
  created_at: string
  updated_at: string
}

export interface RollRequest {
  type: 'attack' | 'save_fort' | 'save_ref' | 'save_will' | 'skill_check' | 'initiative' | 'ability_check'
  skill?: string
  dc?: number
  description: string
}

export interface AdventureMessage {
  id: number
  role: 'player' | 'dm' | 'system'
  content: string
  message_type: 'narrative' | 'sanitization_fail' | 'stage_advance' | 'roll_request' | 'roll_result'
  metadata: {
    roll_request?: RollRequest
    roll_value?: number
    roll_description?: string
  }
  created_at: string
}
