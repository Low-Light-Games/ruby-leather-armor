import { useState, useMemo, useCallback } from 'react';
import type { Adventure, DerivedStats } from '../../../types';
import type { SpellDefinition } from '../../../rules/pathfinder_spells_types';
import { csrfToken } from '../../../utils/api';
import { routes } from '../../../utils/routes';
import {
  getCastingStyle,
  getSpellsForClass,
  getAllSpells,
  hasSlotForSpell,
} from '../../../rules/pathfinder_spells';

export interface SpellbookSearchResult {
  spell: SpellDefinition;
  hasSlot: boolean;
}

interface UseSpellbookResult {
  spellbookSearch: string;
  setSpellbookSearch: (v: string) => void;
  spellbookSaving: boolean;
  spellbookSearchResults: SpellbookSearchResult[];
  addSpellToSpellbook: (spell: SpellDefinition) => void;
}

export function useSpellbook(
  adventure: Adventure | null,
  ds: DerivedStats | null,
  setAdventure: React.Dispatch<React.SetStateAction<Adventure | null>>,
): UseSpellbookResult {
  const [spellbookSearch, setSpellbookSearch] = useState('');
  const [spellbookSaving, setSpellbookSaving] = useState(false);

  const spellbookSearchResults = useMemo((): SpellbookSearchResult[] => {
    if (!adventure || !ds) return [];
    const sheet = adventure.adventure_sheet;
    const castStyle = getCastingStyle(sheet.character_class);
    if (castStyle !== 'spellbook' || !spellbookSearch.trim()) return [];
    const currentSpellIds: string[] = sheet.details?.spellbook || sheet.details?.spells || [];
    const term = spellbookSearch.toLowerCase().trim();
    const classSpells = sheet.character_class
      ? getSpellsForClass(sheet.character_class, 9)
      : getAllSpells();
    return classSpells
      .filter(s => !currentSpellIds.includes(s.id))
      .filter(s => s.name.toLowerCase().includes(term) || s.school.includes(term))
      .map(spell => ({
        spell,
        hasSlot: hasSlotForSpell(
          sheet.character_class, sheet.level,
          ds.final_scores.intelligence, spell, currentSpellIds,
        ),
      }))
      .slice(0, 8);
  }, [adventure, ds, spellbookSearch]);

  const addSpellToSpellbook = useCallback(async (spell: SpellDefinition) => {
    if (!adventure) return;
    const sheet = adventure.adventure_sheet;
    const currentSpellIds: string[] = sheet.details?.spellbook || sheet.details?.spells || [];
    setSpellbookSaving(true);
    try {
      const newSpellbook = [...currentSpellIds, spell.id];
      const res = await fetch(routes.adventureSheet(adventure.id), {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken() },
        body: JSON.stringify({ spellbook: newSpellbook }),
      });
      if (res.ok) {
        const updatedSheet = await res.json();
        setAdventure(prev => prev ? { ...prev, adventure_sheet: updatedSheet } : prev);
      }
    } catch (e) {
      console.error('Failed to update spellbook:', e);
    } finally {
      setSpellbookSaving(false);
      setSpellbookSearch('');
    }
  }, [adventure, setAdventure]);

  return {
    spellbookSearch,
    setSpellbookSearch,
    spellbookSaving,
    spellbookSearchResults,
    addSpellToSpellbook,
  };
}
