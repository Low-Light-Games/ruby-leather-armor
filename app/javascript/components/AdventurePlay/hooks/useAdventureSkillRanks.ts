import { useState, useCallback } from 'react';
import type { Adventure } from '../../../types';
import { csrfToken } from '../../../utils/api';
import type { SkillRanksMap } from '../../../rules/pathfinder_skill_ranks';

interface UseAdventureSkillRanksResult {
  rankSaving: boolean;
  patchSkillRanks: (next: SkillRanksMap) => Promise<void>;
}

export function useAdventureSkillRanks(
  adventure: Adventure | null,
  setAdventure: React.Dispatch<React.SetStateAction<Adventure | null>>,
): UseAdventureSkillRanksResult {
  const [rankSaving, setRankSaving] = useState(false);

  const patchSkillRanks = useCallback(
    async (next: SkillRanksMap) => {
      if (!adventure) return;
      setRankSaving(true);
      try {
        const res = await fetch(`/adventures/${adventure.id}/adventure_sheet`, {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken() },
          body: JSON.stringify({ skill_ranks: next }),
        });
        if (res.ok) {
          const updatedSheet = await res.json();
          setAdventure(prev => (prev ? { ...prev, adventure_sheet: updatedSheet } : prev));
        }
      } catch (e) {
        console.error('Failed to update skill ranks:', e);
      } finally {
        setRankSaving(false);
      }
    },
    [adventure, setAdventure],
  );

  return { rankSaving, patchSkillRanks };
}
