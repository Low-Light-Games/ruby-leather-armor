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
  // Condition data
  active_conditions: string[]
  condition_restrictions: string[]
  // Stat breakdowns (for tooltip display)
  ac_breakdown?: StatBreakdownLine[]
  fort_breakdown?: StatBreakdownLine[]
  ref_breakdown?: StatBreakdownLine[]
  will_breakdown?: StatBreakdownLine[]
}

export interface StatBreakdownLine {
  label: string
  value: number | string
  type?: 'bonus' | 'penalty' | 'base' | 'condition'
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
  hook: string | null
  initial_context: string | null
  initial_summary: string | null
  created_at: string
  updated_at: string
}

export interface AdminStory {
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
  created_at: string
  updated_at: string
}

export interface LocationConnectionData {
  id?: number
  to_location_id: number
  distance_miles: number
  terrain_type: string
  description?: string
  _destroy?: boolean
}

export interface StoryLocationData {
  id?: number
  name: string
  description: string
  starting: boolean
  connections_from?: LocationConnectionData[]
  _destroy?: boolean
}

export interface CreatureManifestEntry {
  bestiary_entry_id: string | null
  count: number
  display_name: string
}

export interface EncounterTableEntryData {
  id?: number
  title: string
  description: string
  entry_type: 'fixed' | 'ai_prompt'
  weight: number
  terrain_types?: string
  min_party_level?: number | null
  max_party_level?: number | null
  creature_manifest?: CreatureManifestEntry[]
  _destroy?: boolean
}

export interface EncounterTableData {
  id?: number
  name: string
  description: string
  check_frequency_hours: number
  encounter_chance: number
  encounter_table_entries?: EncounterTableEntryData[]
  _destroy?: boolean
}

export type NpcSource = 'manual' | 'enricher' | 'embellisher'
export type NpcRole = 'quest_giver' | 'informant' | 'antagonist' | 'bystander' | 'merchant'
export type NpcAttitude = 'friendly' | 'indifferent' | 'unfriendly'

export interface StoryNpcData {
  id?: number
  source: NpcSource
  name: string
  role: NpcRole
  location_id?: number | null
  description: string
  knowledge: string
  attitude: NpcAttitude
  secret: boolean
  _destroy?: boolean
}

export type ClueSource = 'manual' | 'enricher' | 'embellisher'
export type DiscoveryMethod = 'social' | 'exploration' | 'magic' | 'combat' | 'automatic'
export type ClueDifficulty = 'automatic' | 'easy' | 'moderate' | 'hard'

export interface StoryClueData {
  id?: number
  source: ClueSource
  title: string
  description: string
  discovery_method: DiscoveryMethod
  location_id?: number | null
  npc_id?: number | null
  prerequisite_clue_ids: number[]
  reveals_secret: string
  difficulty: ClueDifficulty
  _destroy?: boolean
}

export type MilestoneSource = 'manual' | 'enricher'

export interface StoryMilestoneData {
  id?: number
  source: MilestoneSource
  title: string
  description: string
  trigger_clue_ids: number[]
  consequence: string
  _destroy?: boolean
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
  traversal_context: Record<string, unknown> | null
  combat_context: Record<string, unknown> | null
  social_context: Record<string, unknown> | null
  exploration_context: Record<string, unknown> | null
  rest_context: Record<string, unknown> | null
  inventory_context: Record<string, unknown> | null
  time_context: Record<string, unknown> | null
  story_summary: string | null
  scene_summary: string | null
  current_category: string | null
  directed_dm: boolean
}

export interface AdventureSummary {
  id: number
  character_name: string
  story_title: string
  character_currency: Currency
  created_at: string
  updated_at: string
}

export interface SituationalModifier {
  source: string
  bonus: number
  type?: string
}

export interface RollRequest {
  type: string
  skill?: string
  spell?: string
  dc?: number
  description: string
  domain?: string
  take_10_eligible?: boolean
  take_20_eligible?: boolean
  take_10_value?: number | null
  take_20_value?: number | null
  situational_modifiers?: SituationalModifier[]
}

export interface AdventureMessage {
  id: number
  role: 'player' | 'dm' | 'system'
  content: string
  message_type: 'narrative' | 'sanitization_fail' | 'adventure_complete'
    | 'roll_request' | 'roll_result'
    | 'initiative_request' | 'initiative_result'
    | 'dm_query' | 'usage_limit'
  metadata: {
    roll_request?: RollRequest
    roll_requests?: RollRequest[]
    roll_value?: number
    roll_description?: string
    rolls?: Array<{ roll_value: number; roll_description: string }>
    [key: string]: unknown
  }
  pipeline_run_id?: string | null
  created_at: string
}
