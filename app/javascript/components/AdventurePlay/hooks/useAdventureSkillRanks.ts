import { useState, useCallback } from 'react';
import type { Adventure } from '../../../types';
import { csrfToken } from '../../../utils/api';
import type { SkillRanksMap } from '../../../rules/pathfinder_skill_ranks';

interface UseAdventureSkillRanksResult {
  rankSaving: boolean;
  rankErrors: string[];
  dismissRankErrors: () => void;
  patchSkillRanks: (next: SkillRanksMap) => Promise<void>;
}

function normalizeErrorList(data: { errors?: string[]; error?: string }): string[] {
  if (Array.isArray(data.errors) && data.errors.length > 0) {
    return data.errors.map(e => String(e).trim()).filter(Boolean);
  }
  if (data.error && String(data.error).trim()) {
    return [String(data.error).trim()];
  }
  return ['Could not update skill ranks.'];
}

export function useAdventureSkillRanks(
  adventure: Adventure | null,
  setAdventure: React.Dispatch<React.SetStateAction<Adventure | null>>,
): UseAdventureSkillRanksResult {
  const [rankSaving, setRankSaving] = useState(false);
  const [rankErrors, setRankErrors] = useState<string[]>([]);

  const dismissRankErrors = useCallback(() => setRankErrors([]), []);

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
          setRankErrors([]);
          const updatedSheet = await res.json();
          setAdventure(prev => (prev ? { ...prev, adventure_sheet: updatedSheet } : prev));
        } else {
          const data = (await res.json().catch(() => ({}))) as { errors?: string[]; error?: string };
          setRankErrors(normalizeErrorList(data));
        }
      } catch (e) {
        console.error('Failed to update skill ranks:', e);
        setRankErrors(['Could not update skill ranks.']);
      } finally {
        setRankSaving(false);
      }
    },
    [adventure, setAdventure],
  );

  return { rankSaving, rankErrors, dismissRankErrors, patchSkillRanks };
}
