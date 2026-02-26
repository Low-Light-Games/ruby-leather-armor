import { useMemo } from 'react';
import type { AttributeValues } from '../../../contexts/SheetsContext';
import type { RaceDefinition } from '../../../rules/pathfinder_races';
import type { EquipmentSkillBonuses } from '../../../rules/pathfinder_items_types';
import { PATHFINDER_SKILLS, abilityModifier } from '../../../rules/pathfinder_skills';
import { ABILITY_ABBR } from '../../../utils/formatting';

// ── Public types ──────────────────────────────────────────────────

export interface CalculatedSkill {
  name: string;
  keyAbility: string;
  trainedOnly: boolean;
  armorCheckPenalty: boolean;
  abilityAbbr: string;
  abilityMod: number;
  racialBonus: number;
  featBonus: number;
  equipBonus: number;
  acpPenalty: number;
  total: number;
}

// ── Hook params ──────────────────────────────────────────────────

interface UseSkillsParams {
  finalAttributes: AttributeValues;
  race: RaceDefinition | undefined;
  /** Skill bonuses from feats (e.g. Skill Focus) */
  featSkillBonuses: Record<string, number>;
  /** Skill bonuses from equipped item effects */
  equipSkillBonuses: EquipmentSkillBonuses;
  /** Total armor check penalty (equipment + encumbrance) */
  totalACP: number;
}

// ── Hook result ──────────────────────────────────────────────────

interface UseSkillsResult {
  calculatedSkills: CalculatedSkill[];
  racialSkillBonuses: Record<string, number>;
}

// ── Hook implementation ──────────────────────────────────────────

export function useSkills({
  finalAttributes,
  race,
  featSkillBonuses,
  equipSkillBonuses,
  totalACP,
}: UseSkillsParams): UseSkillsResult {
  // Racial skill bonuses
  const racialSkillBonuses = useMemo(() => {
    const map: Record<string, number> = {};
    if (race) {
      for (const sb of race.skillBonuses) {
        map[sb.skill] = (map[sb.skill] || 0) + sb.bonus;
      }
    }
    return map;
  }, [race]);

  // Skills (with ACP and equipment bonuses)
  const calculatedSkills = useMemo(() => {
    return PATHFINDER_SKILLS.map(skill => {
      const abilityScore = finalAttributes[skill.keyAbility];
      const abilityMod = abilityModifier(abilityScore);
      const racialBonus = racialSkillBonuses[skill.name] || 0;
      const featBonus = featSkillBonuses[skill.name] || 0;
      const equipBonus = equipSkillBonuses[skill.name] || 0;
      const acpPenalty = skill.armorCheckPenalty ? totalACP : 0;
      const total = abilityMod + racialBonus + featBonus + equipBonus + acpPenalty;
      return {
        ...skill,
        abilityAbbr: ABILITY_ABBR[skill.keyAbility],
        abilityMod,
        racialBonus,
        featBonus,
        equipBonus,
        acpPenalty,
        total,
      };
    });
  }, [finalAttributes, racialSkillBonuses, featSkillBonuses, equipSkillBonuses, totalACP]);

  return { calculatedSkills, racialSkillBonuses };
}
