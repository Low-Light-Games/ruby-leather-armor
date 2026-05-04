import type { OwnedItem, Currency } from './rules/pathfinder_items_types';
import type { CombatDiceStrategy } from './types/auth';

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
  /** Flat bonus from active_buff rows targeting `damage` (e.g. inspire courage). */
  damage_bonus: number
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
  rank_bonus?: number
  total: number
}

export interface ActiveBuff {
  source: string
  source_type?: string | null
  bonus_type: string
  target: string
  value: number
  expires_at_game_hours?: number | null
  remaining_hours?: number | null
  duration_label: string
  meta?: Record<string, unknown>
}

export interface Sheet {
  id: number
  name: string
  description: string | null
  details: SheetDetails | null
  /** Same shape as adventure sheets when present on `sheet_json`. */
  class_abilities?: ClassAbilitySummary[]
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
  /** Per-skill rank counts (Pathfinder); independent from `details`. */
  skill_ranks?: Record<string, number>
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

export interface AdminStory {
  id: number
  title: string
  preview: string
  premise: string
  story_locations?: StoryLocationData[]
  encounter_tables?: EncounterTableData[]
  story_npcs?: StoryNpcData[]
  created_at: string
  updated_at: string
}

export interface StoryLocationData {
  id?: number
  name: string
  description: string
  starting: boolean
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

export type NpcSource = 'manual'
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


/** Live slice from ClassAbilityDefinition by class/level; included in builder and adventure `SheetPresenter` JSON. */
export interface ClassAbilitySummary {
  id: string
  name: string
  summary: string | null
}

export interface AdventureSheet {
  id: number
  sheet_id: number | null
  name: string
  description: string | null
  details: SheetDetails | null
  class_abilities?: ClassAbilitySummary[]
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
  /** Per-skill rank counts; adventure copy is independent from the source sheet. */
  skill_ranks?: Record<string, number>
  active_buffs?: ActiveBuff[]
  hp: number
  max_hp: number
  items: string | null       // legacy text field
  effects: string | null
}

/** Active combat tactical snapshot; null when not in combat. */
export interface BattlefieldSnapshot {
  id: number
  version: number
  topology: string
  tokens: Record<string, Record<string, unknown>>
  viewport: Record<string, unknown>
  world: Record<string, unknown>
}

export interface Adventure {
  id: number
  adventure_sheet: AdventureSheet
  story: Story
  battlefield?: BattlefieldSnapshot | null
  combat_context: Record<string, unknown> | null
  time_context: Record<string, unknown> | null
  story_summary: string | null
  scene_summary: string | null
  current_category: string | null
  ended: boolean
  ended_at: string | null
  end_reason: 'player_death' | 'adventure_complete' | null
  directed_dm: boolean
  skip_world_sanity_check: boolean
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
  request_id?: string
  source_request_id?: string
  type: string
  skill?: string
  spell?: string
  dc?: number
  description: string
  domain?: string
  attack_mode?: string
  defense_kind?: string
  source_type?: string
  source_id?: string
  damage?: string
  damage_type?: string
  target?: string
  take_10_eligible?: boolean
  take_20_eligible?: boolean
  take_10_value?: number | null
  take_20_value?: number | null
  situational_modifiers?: SituationalModifier[]
}

// ─── Combat HUD shared types ───
//
// CombatActionEconomyChips and CombatHud are small enough to host their
// component-local types here; CombatGrid and CombatActionPanel are big
// enough to keep their own per-component types files (see their folders).

export interface ActionEconomyShape {
  round?: number | null
  holder?: string | null
  standard_available?: boolean
  move_available?: boolean
  swift_available?: boolean
  full_round_claimed?: boolean
}

export interface CombatActionEconomyChipsProps {
  combatContext: Record<string, unknown> | null
}

export interface ActionEconomyChip {
  key: 'standard' | 'move' | 'swift' | 'free'
  label: string
  available: boolean
  tooltip: string
}

export interface CombatHudProps {
  adventureId: number
  combatContext: Record<string, unknown> | null
  diceStrategy: CombatDiceStrategy
  onDiceStrategyChange: (next: CombatDiceStrategy) => void
  onCombatEnded?: () => void
  onActionResolved?: () => void
}

export interface AdventureMessage {
  id: number
  role: 'player' | 'dm' | 'system'
  content: string
  message_type: 'narrative' | 'sanitization_fail' | 'adventure_complete' | 'player_death'
    | 'player_incapacitated'
    | 'combat_log' | 'combat_end' | 'action_result'
    | 'roll_request' | 'roll_result'
    | 'initiative_request' | 'initiative_result'
    | 'dm_query' | 'usage_limit' | 'system_notice' | 'moderation_flagged'
  metadata: {
    roll_request?: RollRequest
    roll_requests?: RollRequest[]
    roll_value?: number
    roll_description?: string
    rolls?: Array<{ roll_value: number; roll_description: string; request_id?: string }>
    sequence_index?: number
    total_actions?: number
    action_text?: string | null
    [key: string]: unknown
  }
  registry_entry_uuid?: string | null
  created_at: string
}
