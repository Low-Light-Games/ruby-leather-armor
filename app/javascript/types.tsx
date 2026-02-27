import type { OwnedItem, Currency } from './rules/pathfinder_items_types';

export interface SheetDetails {
  feats?: string[]          // feat IDs

  // ─── Spell storage (differentiated by casting style) ───
  /** Spontaneous casters (sorcerer, bard): their limited known spells */
  knownSpells?: string[]
  /** Wizard: spells copied into the spellbook */
  spellbook?: string[]
  /** @deprecated Legacy field — migrated to knownSpells or spellbook on load */
  spells?: string[]

  // ─── Items / Equipment ───
  items?: OwnedItem[]
}

/** Server-computed derived stats (see CharacterStats::Calculator). */
export interface DerivedStats {
  final_scores: Record<string, number>
  mods: Record<string, number>
  bab: number
  fort: number
  ref: number
  will: number
  ac: number
  touch_ac: number
  flat_footed_ac: number
  cmb: number
  cmd: number
  initiative: number
  max_hp: number
  hp_bonus: number
  melee_attack: number
  ranged_attack: number
  speed: number
  size: string
  skills: DerivedSkill[]
  feat_stat_bonuses: {
    ac: number
    fort_save: number
    ref_save: number
    will_save: number
    initiative: number
    melee_attack: number
    ranged_attack: number
    hp: number
    cmb_by_maneuver: Record<string, number>
    cmd_by_maneuver: Record<string, number>
  }
  // Equipment-derived stats
  armor_bonus: number
  shield_bonus: number
  armor_check_penalty: number
  arcane_spell_failure: number
  max_dex_bonus: number | null
  total_weight: number
  carry_capacity: {
    light: number
    medium: number
    heavy: number
  }
  encumbrance: string
}

export interface DerivedSkill {
  name: string
  key_ability: string
  trained_only: boolean
  ability_mod: number
  racial_bonus: number
  feat_bonus: number
  equip_bonus?: number
  acp_penalty?: number
  total: number
}

export interface Sheet {
  id: number
  name: string
  description: string | null
  details: SheetDetails | null
  derived_stats: DerivedStats
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
  currency: Currency
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
  initial_context: string | null
  created_at: string
  updated_at: string
}

export interface AdminStory {
  id: number
  title: string
  preview: string
  premise: string
  initial_context: string | null
  created_at: string
  updated_at: string
}

export interface AdventureSheet {
  id: number
  sheet_id: number | null
  name: string
  description: string | null
  details: SheetDetails | null
  derived_stats: DerivedStats
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
  currency: Currency
  hp: number
  max_hp: number
  items: string | null       // legacy text field
  effects: string | null
}

export interface Adventure {
  id: number
  adventure_sheet: AdventureSheet
  story: Story
  immediate_context: string | null
  story_summary: string | null
  current_category: string | null
}

export interface AdventureSummary {
  id: number
  character_name: string
  story_title: string
  character_currency: Currency
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
  message_type: 'narrative' | 'sanitization_fail' | 'adventure_complete' | 'roll_request' | 'roll_result'
  metadata: {
    roll_request?: RollRequest
    roll_value?: number
    roll_description?: string
  }
  created_at: string
}
