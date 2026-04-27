import { useState, useEffect, useCallback, useMemo } from 'react';
import type { Adventure, AdventureSheet, DerivedStats, AttributeType } from '../../../types';

const ATTRIBUTE_KEYS: AttributeType[] = [
  'strength',
  'dexterity',
  'constitution',
  'intelligence',
  'wisdom',
  'charisma',
];

function abilityModifier(score: number): number {
  return Math.floor((score - 10) / 2);
}

function buildFallbackDerivedStats(sheet: AdventureSheet): DerivedStats {
  const finalScores = ATTRIBUTE_KEYS.reduce<Record<string, number>>((acc, attr) => {
    acc[attr] = sheet[attr] ?? 10;
    return acc;
  }, {});

  const mods = ATTRIBUTE_KEYS.reduce<Record<string, number>>((acc, attr) => {
    acc[attr] = abilityModifier(finalScores[attr] ?? 10);
    return acc;
  }, {});

  return {
    final_scores: finalScores,
    mods,
    bab: 0,
    fort: 0,
    ref: 0,
    will: 0,
    ac: 10,
    touch_ac: 10,
    flat_footed_ac: 10,
    cmb: mods.strength ?? 0,
    cmd: 10 + (mods.strength ?? 0) + (mods.dexterity ?? 0),
    initiative: mods.dexterity ?? 0,
    max_hp: sheet.max_hp ?? 0,
    hp_bonus: 0,
    melee_attack: mods.strength ?? 0,
    ranged_attack: mods.dexterity ?? 0,
    damage_bonus: 0,
    speed: 30,
    size: 'medium',
    skills: [],
    feat_stat_bonuses: {
      ac: 0,
      fort_save: 0,
      ref_save: 0,
      will_save: 0,
      initiative: 0,
      melee_attack: 0,
      ranged_attack: 0,
      hp: 0,
      cmb_by_maneuver: {},
      cmd_by_maneuver: {},
    },
    armor_bonus: 0,
    shield_bonus: 0,
    armor_check_penalty: 0,
    arcane_spell_failure: 0,
    max_dex_bonus: null,
    total_weight: 0,
    carry_capacity: {
      light: 0,
      medium: 0,
      heavy: 0,
    },
    encumbrance: 'light',
    active_conditions: [],
    condition_restrictions: [],
  };
}

function normalizeDerivedStats(sheet: AdventureSheet | null | undefined): DerivedStats | null {
  if (!sheet) return null;

  const fallback = buildFallbackDerivedStats(sheet);
  const raw = sheet.derived_stats;

  if (!raw || typeof raw !== 'object') return fallback;

  return {
    ...fallback,
    ...raw,
    final_scores: { ...fallback.final_scores, ...(raw.final_scores ?? {}) },
    mods: { ...fallback.mods, ...(raw.mods ?? {}) },
    skills: Array.isArray(raw.skills) ? raw.skills : fallback.skills,
    feat_stat_bonuses: {
      ...fallback.feat_stat_bonuses,
      ...(raw.feat_stat_bonuses ?? {}),
      cmb_by_maneuver: {
        ...fallback.feat_stat_bonuses.cmb_by_maneuver,
        ...(raw.feat_stat_bonuses?.cmb_by_maneuver ?? {}),
      },
      cmd_by_maneuver: {
        ...fallback.feat_stat_bonuses.cmd_by_maneuver,
        ...(raw.feat_stat_bonuses?.cmd_by_maneuver ?? {}),
      },
    },
    carry_capacity: {
      ...fallback.carry_capacity,
      ...(raw.carry_capacity ?? {}),
    },
    active_conditions: Array.isArray(raw.active_conditions) ? raw.active_conditions : fallback.active_conditions,
    condition_restrictions: Array.isArray(raw.condition_restrictions)
      ? raw.condition_restrictions
      : fallback.condition_restrictions,
  };
}

interface UseAdventureResult {
  adventure: Adventure | null;
  ds: DerivedStats | null;
  loading: boolean;
  error: string | null;
  /** Reload the adventure from the server (e.g. after stage advance). */
  reload: () => void;
  /** Replace the in-memory adventure (e.g. after spellbook patch). */
  setAdventure: React.Dispatch<React.SetStateAction<Adventure | null>>;
}

export function useAdventure(adventureId: number, user: unknown): UseAdventureResult {
  const [adventure, setAdventure] = useState<Adventure | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const loadAdventure = useCallback(() => {
    if (!user) return;

    fetch(`/adventures/${adventureId}.json`, { cache: 'no-store' })
      .then(response => {
        if (!response.ok) throw new Error('Failed to load adventure');
        return response.json();
      })
      .then(data => {
        setAdventure(data);
        setLoading(false);
      })
      .catch(err => {
        console.error('Error loading adventure:', err);
        setError(err.message);
        setLoading(false);
      });
  }, [user, adventureId]);

  useEffect(() => {
    loadAdventure();
  }, [loadAdventure]);

  const ds: DerivedStats | null = useMemo(
    () => normalizeDerivedStats(adventure?.adventure_sheet),
    [adventure?.adventure_sheet],
  );

  return { adventure, ds, loading, error, reload: loadAdventure, setAdventure };
}
