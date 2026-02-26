import { useState, useMemo, useCallback } from 'react';
import type { Dispatch, SetStateAction } from 'react';
import type { ClassDefinition } from '../../../rules/pathfinder_classes';
import {
  getAllSpells,
  getSpellById,
  getSpellsForClass,
  isSpellcaster,
  castingStartLevel,
  maxSpellLevelForClass,
  checkSpellEligibility,
  canSelectSpell,
  getCastingStyle,
  computeSpellSlots,
  hasSlotForSpell,
} from '../../../rules/pathfinder_spells';
import type { SpellSlotSummary, SpellEligibility } from '../../../rules/pathfinder_spells';
import type { SpellDefinition } from '../../../rules/pathfinder_spells_types';

// ── Public types ──────────────────────────────────────────────────

export interface SelectedSpellEligibility {
  spell: SpellDefinition;
  eligibility: SpellEligibility;
}

export interface FilteredSpellWithChecks {
  spell: SpellDefinition;
  eligibility: SpellEligibility;
  selectable: boolean;
  slotReason?: string;
}

export type CastingStyleLabel = 'spontaneous' | 'spellbook' | 'prepared_list' | null;

// ── Hook params ──────────────────────────────────────────────────

interface UseSpellsParams {
  selectedSpells: string[];
  setSelectedSpells: Dispatch<SetStateAction<string[]>>;
  currentClass: string | null;
  classDef: ClassDefinition | undefined;
  currentLevel: number;
  intelligenceScore: number;
}

// ── Hook result ──────────────────────────────────────────────────

interface UseSpellsResult {
  // Search state
  spellSearch: string;
  setSpellSearch: (v: string) => void;

  // Actions
  addSpell: (spellId: string) => void;
  removeSpell: (spellId: string) => void;

  // Casting info
  castingStyle: CastingStyleLabel;
  classCasts: boolean;
  castingUnlocked: boolean;
  classStartLevel: number | null;
  currentMaxSpellLevel: number;
  spellSlots: SpellSlotSummary[];
  spellSectionLabel: string;

  // Derived lists
  filteredSpellsWithChecks: FilteredSpellWithChecks[];
  selectedSpellEligibilities: SelectedSpellEligibility[];
}

// ── Hook implementation ──────────────────────────────────────────

export function useSpells({
  selectedSpells,
  setSelectedSpells,
  currentClass,
  classDef,
  currentLevel,
  intelligenceScore,
}: UseSpellsParams): UseSpellsResult {
  const [spellSearch, setSpellSearch] = useState('');

  // ── Actions ─────────────────────────────────────────────────────

  const addSpell = useCallback((spellId: string) => {
    setSelectedSpells(prev => prev.includes(spellId) ? prev : [...prev, spellId]);
    setSpellSearch('');
  }, [setSelectedSpells]);

  const removeSpell = useCallback((spellId: string) => {
    setSelectedSpells(prev => prev.filter(id => id !== spellId));
  }, [setSelectedSpells]);

  // ── Casting metadata ────────────────────────────────────────────

  const rawCastingStyle = useMemo(() => getCastingStyle(currentClass), [currentClass]);
  const castingStyle: CastingStyleLabel = rawCastingStyle === 'none' ? null : rawCastingStyle;

  const classCasts = useMemo(() => isSpellcaster(currentClass), [currentClass]);

  const classStartLevel = useMemo(() => castingStartLevel(currentClass), [currentClass]);

  const castingUnlocked = useMemo(() => {
    if (!currentClass || !classCasts) return false;
    return maxSpellLevelForClass(currentClass, currentLevel) >= 0;
  }, [currentClass, classCasts, currentLevel]);

  const currentMaxSpellLevel = useMemo(
    () => maxSpellLevelForClass(currentClass, currentLevel),
    [currentClass, currentLevel],
  );

  const spellSlots = useMemo<SpellSlotSummary[]>(
    () => computeSpellSlots(currentClass, currentLevel, intelligenceScore, selectedSpells),
    [currentClass, currentLevel, intelligenceScore, selectedSpells],
  );

  const spellSectionLabel = useMemo(() => {
    switch (castingStyle) {
      case 'spellbook': return 'Spellbook';
      case 'spontaneous': return 'Known Spells';
      case 'prepared_list': return 'Spells';
      default: return 'Spells';
    }
  }, [castingStyle]);

  // ── Available / filtered spells ─────────────────────────────────

  const availableSpells = useMemo(() => {
    if (!currentClass) return getAllSpells();
    if (!classCasts) return [];
    return getSpellsForClass(currentClass, 9);
  }, [currentClass, classCasts]);

  const filteredSpellsWithChecks = useMemo(() => {
    const term = spellSearch.toLowerCase().trim();
    if (!term) return [];
    return availableSpells
      .filter(s => !selectedSpells.includes(s.id))
      .filter(s => s.name.toLowerCase().includes(term) || s.school.includes(term))
      .map(spell => {
        if (!currentClass) {
          return {
            spell,
            eligibility: { status: 'available' as const, spellLevel: Object.values(spell.classLevels)[0] ?? undefined },
            selectable: true,
            slotReason: undefined,
          };
        }
        const eligibility = checkSpellEligibility(currentClass, currentLevel, spell);
        const eligible = canSelectSpell(eligibility);
        const hasSlot = eligible
          ? hasSlotForSpell(currentClass, currentLevel, intelligenceScore, spell, selectedSpells)
          : false;
        const selectable = eligible && hasSlot;
        const slotReason = eligible && !hasSlot ? 'Spell slots full for this level' : undefined;
        return { spell, eligibility, selectable, slotReason };
      })
      .slice(0, 12);
  }, [spellSearch, selectedSpells, availableSpells, currentClass, currentLevel, intelligenceScore]);

  // ── Selected spells with eligibility ────────────────────────────

  const selectedSpellDefs = useMemo(
    () => selectedSpells.map(id => getSpellById(id)).filter(Boolean) as SpellDefinition[],
    [selectedSpells],
  );

  const selectedSpellEligibilities = useMemo(() => {
    return selectedSpellDefs.map(spell => ({
      spell,
      eligibility: checkSpellEligibility(currentClass, currentLevel, spell),
    }));
  }, [selectedSpellDefs, currentClass, currentLevel]);

  return {
    spellSearch,
    setSpellSearch,
    addSpell,
    removeSpell,
    castingStyle,
    classCasts,
    castingUnlocked,
    classStartLevel,
    currentMaxSpellLevel,
    spellSlots,
    spellSectionLabel,
    filteredSpellsWithChecks,
    selectedSpellEligibilities,
  };
}
