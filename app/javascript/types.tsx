export interface Sheet {
  id: number
  name: string
  description: string | null
  details: Record<string, any> | null
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

export interface CharacterSnapshot {
  name: string
  description: string | null
  strength: number
  intelligence: number
  dexterity: number
  constitution: number
  wisdom: number
  charisma: number
  race: string | null
  racial_bonus_attribute: string | null
  character_class: string | null
}

export interface Adventure {
  id: number
  character_snapshot: CharacterSnapshot
  story_state: StoryState
  story: Story
  character_gold: number
  character_hp: number
  character_max_hp: number
  character_effects: string | null
  character_items: string | null
}

export interface AdventureSummary {
  id: number
  character_name: string
  story_title: string
  character_gold: number
  created_at: string
  updated_at: string
}
