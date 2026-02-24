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
  created_at: string
  updated_at: string
}

export interface Adventure {
  id: number
  sheet: Sheet
  story_state: StoryState
  story: Story
  character_gold: number
  character_effects: string | null
  character_items: string | null
}
