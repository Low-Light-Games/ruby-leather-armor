import { AttributeType } from '../types';
import { ABILITY_ABBR } from '../utils/formatting';
import { FeatDefinition, FeatCategory, FeatEffect, Prerequisite } from './pathfinder_feats_types';
import type { BABProgression } from './pathfinder_classes';

export type { FeatDefinition, FeatCategory } from './pathfinder_feats_types';
export type { Prerequisite, FeatEffect, BonusTarget } from './pathfinder_feats_types';

let ALL_FEATS: FeatDefinition[] = [];

export function setFeatDefinitions(feats: FeatDefinition[]): void {
  ALL_FEATS = feats;
}

export function getAllFeats(): FeatDefinition[] {
  return ALL_FEATS;
}

// A feat entry is `"feat_id"` or `"feat_id::choice"`, e.g. `"skill_focus::Perception"`.
export interface ParsedFeatEntry {
  featId: string;
  choice: string | null;
  raw: string;
}

export const FEAT_CHOICE_SEPARATOR = '::';

export function parseFeatEntry(entry: string): ParsedFeatEntry {
  const separatorIndex = entry.indexOf(FEAT_CHOICE_SEPARATOR);
  if (separatorIndex === -1) return { featId: entry, choice: null, raw: entry };
  return {
    featId: entry.substring(0, separatorIndex),
    choice: entry.substring(separatorIndex + FEAT_CHOICE_SEPARATOR.length),
    raw: entry,
  };
}

export function buildFeatEntry(featId: string, choice: string | null): string {
  return choice ? `${featId}${FEAT_CHOICE_SEPARATOR}${choice}` : featId;
}

export function getFeatById(id: string): FeatDefinition | undefined {
  const { featId } = parseFeatEntry(id);
  return ALL_FEATS.find(f => f.id === featId);
}

export function getFeatsByCategory(category: FeatCategory): FeatDefinition[] {
  return ALL_FEATS.filter(f => f.category === category);
}

export function getEntryFeats(): FeatDefinition[] {
  return ALL_FEATS.filter(f => f.prerequisites.length === 0);
}

// Only feat-chain prerequisites; ability scores, BAB and the rest are checkAllPrerequisites' job.
export function hasFeatPrerequisites(
  targetFeatId: string,
  ownedFeatIds: Set<string>,
): boolean {
  const feat = getFeatById(targetFeatId);
  if (!feat) return false;
  return feat.prerequisites
    .filter(p => p.type === 'feat')
    .every(p => ownsBaseFeat(ownedFeatIds, (p as { type: 'feat'; feat: string }).feat));
}

export function computeBAB(bab: BABProgression, level: number): number {
  switch (bab) {
    case 'full':  return level;
    case '3/4':   return Math.floor(level * 3 / 4);
    case '1/2':   return Math.floor(level / 2);
  }
}

export function computeBaseSave(good: boolean, level: number): number {
  if (good) return Math.floor(level / 2) + 2;
  return Math.floor((level - 1) / 3);
}

export interface PrerequisiteContext {
  finalAttributes: Record<AttributeType, number>;
  level: number;
  classId: string | null;
  bab: number;
  ownedFeatIds: Set<string>;
}

function ownsBaseFeat(ownedFeatIds: Set<string>, requiredId: string): boolean {
  if (ownedFeatIds.has(requiredId)) return true;
  for (const entry of ownedFeatIds) {
    const { featId } = parseFeatEntry(entry);
    if (featId === requiredId) return true;
  }
  return false;
}

// 'unknown' covers prerequisites the sheet can't verify; they warn but don't block selection.
export type PrereqStatus = 'met' | 'unmet' | 'unknown';

export interface PrerequisiteCheck {
  label: string;
  status: PrereqStatus;
}

export function prerequisiteLabel(prereq: Prerequisite): string {
  switch (prereq.type) {
    case 'ability':
      return `${ABILITY_ABBR[prereq.ability] || prereq.ability} ${prereq.minimum}+`;
    case 'bab':
      return `BAB +${prereq.minimum}`;
    case 'feat': {
      const f = getFeatById(prereq.feat);
      return f ? f.name : prereq.feat;
    }
    case 'skill':
      return `${prereq.skill} ${prereq.ranks} ranks`;
    case 'caster_level':
      return `Caster level ${prereq.minimum}`;
    case 'class_ability':
      return prereq.feature;
    case 'class_level': {
      const name = prereq.classId.charAt(0).toUpperCase() + prereq.classId.slice(1);
      return `${name} level ${prereq.level}`;
    }
    case 'character_level':
      return `Character level ${prereq.minimum}`;
    case 'proficiency':
      return `${prereq.weapon} proficiency`;
  }
}

export function checkAllPrerequisites(
  feat: FeatDefinition,
  ctx: PrerequisiteContext,
): PrerequisiteCheck[] {
  return feat.prerequisites.map(prereq => {
    const label = prerequisiteLabel(prereq);
    let status: PrereqStatus;

    switch (prereq.type) {
      case 'ability':
        status = ctx.finalAttributes[prereq.ability] >= prereq.minimum ? 'met' : 'unmet';
        break;
      case 'bab':
        status = ctx.bab >= prereq.minimum ? 'met' : 'unmet';
        break;
      case 'feat':
        status = ownsBaseFeat(ctx.ownedFeatIds, prereq.feat) ? 'met' : 'unmet';
        break;
      case 'character_level':
        status = ctx.level >= prereq.minimum ? 'met' : 'unmet';
        break;
      case 'class_level':
        status = (ctx.classId === prereq.classId && ctx.level >= prereq.level) ? 'met' : 'unmet';
        break;
      default:
        status = 'unknown';
    }

    return { label, status };
  });
}

export function canSelectFeat(checks: PrerequisiteCheck[]): boolean {
  return !checks.some(c => c.status === 'unmet');
}

const CHOSEN_SKILL_PLACEHOLDER = 'chosen skill';

export function computeFeatSkillBonuses(featEntries: string[]): Record<string, number> {
  const bonuses: Record<string, number> = {};

  for (const entry of featEntries) {
    const { featId, choice } = parseFeatEntry(entry);
    const feat = ALL_FEATS.find(f => f.id === featId);
    if (!feat) continue;

    for (const effect of feat.effects) {
      if (effect.type !== 'skill_bonus') continue;

      let targetSkill = effect.skill;
      if (targetSkill === CHOSEN_SKILL_PLACEHOLDER) {
        if (!choice) continue;
        targetSkill = choice;
      }

      bonuses[targetSkill] = (bonuses[targetSkill] || 0) + effect.bonus;
    }
  }

  return bonuses;
}

export function featDisplayName(entry: string): string {
  const { featId, choice } = parseFeatEntry(entry);
  const feat = ALL_FEATS.find(f => f.id === featId);
  const baseName = feat?.name ?? featId;
  return choice ? `${baseName} (${choice})` : baseName;
}

// Conditional bonuses ("when fighting defensively", ...) are left out; they apply at roll time.
export interface FeatStatBonuses {
  ac: number;
  fortSave: number;
  refSave: number;
  willSave: number;
  initiative: number;
  meleeAttack: number;
  rangedAttack: number;
  hp: number;
  cmbByManeuver: Record<string, number>;
  cmdByManeuver: Record<string, number>;
}

export function computeFeatStatBonuses(featEntries: string[], characterLevel: number): FeatStatBonuses {
  const result: FeatStatBonuses = {
    ac: 0,
    fortSave: 0,
    refSave: 0,
    willSave: 0,
    initiative: 0,
    meleeAttack: 0,
    rangedAttack: 0,
    hp: 0,
    cmbByManeuver: {},
    cmdByManeuver: {},
  };

  for (const entry of featEntries) {
    const { featId } = parseFeatEntry(entry);
    const feat = ALL_FEATS.find(f => f.id === featId);
    if (!feat) continue;

    for (const effect of feat.effects) {
      switch (effect.type) {
        case 'bonus': {
          if (effect.condition) break;

          switch (effect.target) {
            case 'ac':
              result.ac += effect.bonus;
              break;
            case 'fort_save':
              result.fortSave += effect.bonus;
              break;
            case 'ref_save':
              result.refSave += effect.bonus;
              break;
            case 'will_save':
              result.willSave += effect.bonus;
              break;
            case 'all_saves':
              result.fortSave += effect.bonus;
              result.refSave += effect.bonus;
              result.willSave += effect.bonus;
              break;
            case 'initiative':
              result.initiative += effect.bonus;
              break;
            case 'attack':
              result.meleeAttack += effect.bonus;
              result.rangedAttack += effect.bonus;
              break;
            case 'melee_attack':
              result.meleeAttack += effect.bonus;
              break;
            case 'ranged_attack':
              result.rangedAttack += effect.bonus;
              break;
          }
          break;
        }

        case 'hp_bonus': {
          const hpFromFeat = Math.max(
            effect.perLevel * characterLevel,
            effect.minimum ?? 0,
          );
          result.hp += hpFromFeat;
          break;
        }

        case 'combat_maneuver': {
          const maneuver = effect.maneuver;
          result.cmbByManeuver[maneuver] = (result.cmbByManeuver[maneuver] || 0) + effect.cmbBonus;
          result.cmdByManeuver[maneuver] = (result.cmdByManeuver[maneuver] || 0) + effect.cmdBonus;
          break;
        }
      }
    }
  }

  return result;
}
