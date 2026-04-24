/**
 * Type definitions for Pathfinder 1e Core Rulebook feats.
 * All content is Open Game Content — mechanical rules only.
 */

import { AttributeType } from '../types';

// ─── Feat Category ───────────────────────────────────────────

export type FeatCategory = 'combat' | 'general' | 'metamagic' | 'item_creation';

// ─── Prerequisites ───────────────────────────────────────────

export type Prerequisite =
  | { type: 'ability'; ability: AttributeType; minimum: number }
  | { type: 'bab'; minimum: number }
  | { type: 'feat'; feat: string }              // references FeatDefinition.id
  | { type: 'skill'; skill: string; ranks: number }
  | { type: 'caster_level'; minimum: number }
  | { type: 'class_ability'; feature: string }
  | { type: 'class_level'; classId: string; level: number }
  | { type: 'character_level'; minimum: number }
  | { type: 'proficiency'; weapon: string };

// ─── Feat Effects ────────────────────────────────────────────

export type BonusTarget =
  | 'attack' | 'melee_attack' | 'ranged_attack'
  | 'damage' | 'melee_damage' | 'ranged_damage'
  | 'ac'
  | 'fort_save' | 'ref_save' | 'will_save' | 'all_saves'
  | 'initiative'
  | 'cmb' | 'cmd'
  | 'speed'
  | 'caster_level' | 'concentration' | 'sr_check'
  | 'critical_confirm';

export type FeatEffect =
  // ── Flat or conditional bonus ──
  | {
      type: 'bonus';
      target: BonusTarget;
      bonus: number;
      bonusType?: string;
      condition?: string;
    }

  // ── Skill bonus with optional 10-rank upgrade ──
  | {
      type: 'skill_bonus';
      skill: string;
      bonus: number;
      when10Ranks?: number;
    }

  // ── Hit point bonus ──
  | {
      type: 'hp_bonus';
      perLevel: number;
      minimum?: number;
    }

  // ── Scaling attack ↔ damage trade (Power Attack, Deadly Aim) ──
  | {
      type: 'attack_damage_trade';
      attackPenalty: number;
      damageBonus: number;
      twoHandedDamageBonus?: number;
      scalingPerBAB: number;
    }

  // ── Scaling attack ↔ AC trade (Combat Expertise) ──
  | {
      type: 'attack_ac_trade';
      attackPenalty: number;
      acBonus: number;
      acBonusType: string;
      scalingPerBAB: number;
    }

  // ── Combat maneuver improvement ──
  | {
      type: 'combat_maneuver';
      maneuver: string;
      cmbBonus: number;
      cmdBonus: number;
      noAoO?: boolean;
      additionalEffect?: string;
    }

  // ── Two-weapon fighting penalty reduction ──
  | {
      type: 'twf_penalty_reduction';
      mainHandReduction: number;
      offHandReduction: number;
    }

  // ── Extra attacks of opportunity per round ──
  | { type: 'extra_aoo'; perRound: 'dex_mod' }

  // ── Extra attack per round ──
  | {
      type: 'extra_attack';
      attackType: string;
      penalty: number;
      condition?: string;
    }

  // ── Replace ability modifier for a roll ──
  | {
      type: 'replace_modifier';
      from: string;
      to: string;
      forRoll: string;
    }

  // ── Proficiency grant ──
  | { type: 'proficiency'; category: string }

  // ── Double critical threat range ──
  | { type: 'double_threat_range'; weapon: string }

  // ── Ignore damage reduction ──
  | { type: 'ignore_dr'; amount: number; condition?: string }

  // ── Reroll a failed roll ──
  | { type: 'reroll'; target: string; usesPerDay: number }

  // ── On-critical hit effect ──
  | {
      type: 'on_critical';
      effect: string;
      save?: { saveType: 'fort' | 'ref' | 'will'; dc: string };
    }

  // ── Metamagic spell modification ──
  | { type: 'metamagic'; levelIncrease: number; effect: string }

  // ── Item creation ability ──
  | { type: 'item_creation'; itemType: string; casterLevelRequired: number }

  // ── Extra class resource uses ──
  | { type: 'extra_resource'; resource: string; amount: number }

  // ── Reduce arcane spell failure ──
  | { type: 'reduce_arcane_failure'; reduction: number; armorCategory: string }

  // ── Summoning enhancement ──
  | { type: 'summoning_bonus'; stat: string; bonus: number }

  // ── Spell DC bonus ──
  | { type: 'spell_dc_bonus'; bonus: number; school?: string }

  // ── Extra weapon damage dice (Vital Strike) ──
  | { type: 'extra_weapon_dice'; multiplier: number }

  // ── Negate a penalty ──
  | { type: 'negate_penalty'; penalty: string; description: string }

  // ── Deflect ranged attack ──
  | { type: 'deflect'; target: string; usesPerRound: number }

  // ── Miss chance ──
  | { type: 'miss_chance'; percent: number; condition: string }

  // ── Daily-use ability ──
  | {
      type: 'daily_use';
      name: string;
      usesPerDay: number | string;
      effect: string;
      save?: { saveType: 'fort' | 'ref' | 'will'; dc: string };
    }

  // ── New action type ──
  | {
      type: 'action';
      actionType: 'full_round' | 'standard' | 'move' | 'swift' | 'immediate' | 'free';
      name: string;
      effect: string;
    }

  // ── Movement modification ──
  | { type: 'movement'; description: string }

  // ── Concealment miss chance reroll ──
  | { type: 'concealment_reroll'; description: string }

  // ── Full STR bonus to off-hand attacks ──
  | { type: 'offhand_full_str' }

  // ── Charge damage multiplier (mounted charge) ──
  | { type: 'charge_damage_multiplier'; multiplier: number; condition?: string }

  // ── Mounted combat ability ──
  | { type: 'mounted'; description: string }

  // ── Special (fallback — entries tracked in FEATS_SPELLS_TODO.md) ──
  | { type: 'special'; description: string };

// ─── Feat Definition ─────────────────────────────────────────

export interface FeatDefinition {
  id: string;
  name: string;
  category: FeatCategory;
  prerequisites: Prerequisite[];
  effects: FeatEffect[];
  repeatable: boolean;
  choiceType?: 'weapon' | 'skill' | 'school';
  summary: string;
}
