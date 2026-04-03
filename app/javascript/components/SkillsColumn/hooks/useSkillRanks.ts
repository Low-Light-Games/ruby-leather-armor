import { useMemo, useCallback } from 'react';
import type { Dispatch, SetStateAction } from 'react';
import type { ClassDefinition } from '../../../rules/pathfinder_classes';
import { abilityModifier } from '../../../rules/pathfinder_skills';
import type { SkillRanksMap } from '../../../rules/pathfinder_skill_ranks';
import {
  spentSkillPoints,
  totalSkillPoints,
  tryAdjustSkillRank,
} from '../../../rules/pathfinder_skill_ranks';

interface UseSkillRanksParams {
  skillRanks: SkillRanksMap;
  setSkillRanks: Dispatch<SetStateAction<SkillRanksMap>>;
  currentClass: string | null;
  currentLevel: number;
  currentRace: string | null;
  /** Final Intelligence (after racial modifiers) for skill-point budget. */
  intelligenceScore: number;
  classDef: ClassDefinition | undefined;
  onSheetDirty?: () => void;
}

export interface SkillPointsSummary {
  spent: number;
  total: number;
  remaining: number;
}

export interface UseSkillRanksResult {
  canAssignRanks: boolean;
  pointsSummary: SkillPointsSummary | null;
  adjustRank: (skillName: string, delta: 1 | -1) => void;
}

export function useSkillRanks({
  skillRanks,
  setSkillRanks,
  currentClass,
  currentLevel,
  currentRace,
  intelligenceScore,
  classDef,
  onSheetDirty,
}: UseSkillRanksParams): UseSkillRanksResult {
  const intMod = abilityModifier(intelligenceScore);

  const pointsSummary = useMemo((): SkillPointsSummary | null => {
    if (!currentClass || !classDef) return null;
    const total = totalSkillPoints(currentLevel, intMod, classDef.skillPointsBase, currentRace);
    const spent = spentSkillPoints(skillRanks, currentClass);
    return { spent, total, remaining: Math.max(0, total - spent) };
  }, [currentClass, classDef, currentLevel, intMod, currentRace, skillRanks]);

  const adjustRank = useCallback(
    (skillName: string, delta: 1 | -1) => {
      if (!currentClass || !classDef) return;
      const next = tryAdjustSkillRank(skillRanks, skillName, delta, {
        classId: currentClass,
        level: currentLevel,
        intMod,
        skillPointsBase: classDef.skillPointsBase,
        raceId: currentRace,
      });
      if (!next) return;
      setSkillRanks(next);
      onSheetDirty?.();
    },
    [
      classDef,
      currentClass,
      currentLevel,
      intMod,
      currentRace,
      onSheetDirty,
      setSkillRanks,
      skillRanks,
    ],
  );

  return {
    canAssignRanks: Boolean(currentClass && classDef),
    pointsSummary,
    adjustRank,
  };
}
