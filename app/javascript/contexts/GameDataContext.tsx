/**
 * GameDataContext — fetches and caches feat/spell definitions from the API.
 *
 * Wrap any SPA root that needs game rule data in <GameDataProvider>.
 * Children won't render until both feats and spells have loaded.
 *
 * The loaded data is also pushed into the module-level caches inside
 * `pathfinder_feats.ts` and `pathfinder_spells.ts` so that all helper
 * functions (getFeatById, getSpellById, etc.) work unchanged.
 */

import React, { createContext, useContext, useEffect, useState, useMemo } from 'react';
import type { FeatDefinition } from '../rules/pathfinder_feats_types';
import type { SpellDefinition } from '../rules/pathfinder_spells_types';
import { setFeatDefinitions } from '../rules/pathfinder_feats';
import { setSpellDefinitions } from '../rules/pathfinder_spells';

// ─── Context shape ──────────────────────────────────────────

interface GameDataContextValue {
  feats: FeatDefinition[];
  spells: SpellDefinition[];
  loading: boolean;
  error: string | null;
}

const GameDataContext = createContext<GameDataContextValue>({
  feats: [],
  spells: [],
  loading: true,
  error: null,
});

export const useGameData = () => useContext(GameDataContext);

// ─── Provider ───────────────────────────────────────────────

interface Props {
  children: React.ReactNode;
}

export const GameDataProvider: React.FC<Props> = ({ children }) => {
  const [feats, setFeats] = useState<FeatDefinition[]>([]);
  const [spells, setSpells] = useState<SpellDefinition[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    const load = async () => {
      try {
        const [featsRes, spellsRes] = await Promise.all([
          fetch('/feat_definitions.json'),
          fetch('/spell_definitions.json'),
        ]);

        if (!featsRes.ok) throw new Error(`Feats fetch failed: ${featsRes.status}`);
        if (!spellsRes.ok) throw new Error(`Spells fetch failed: ${spellsRes.status}`);

        const featsData: FeatDefinition[] = await featsRes.json();
        const spellsData: SpellDefinition[] = await spellsRes.json();

        if (cancelled) return;

        // Push data into the module-level caches so helper functions work
        setFeatDefinitions(featsData);
        setSpellDefinitions(spellsData);

        setFeats(featsData);
        setSpells(spellsData);
      } catch (err) {
        if (!cancelled) {
          console.error('Failed to load game data:', err);
          setError(err instanceof Error ? err.message : 'Unknown error');
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    };

    load();
    return () => { cancelled = true; };
  }, []);

  const value = useMemo(
    () => ({ feats, spells, loading, error }),
    [feats, spells, loading, error],
  );

  return (
    <GameDataContext.Provider value={value}>
      {children}
    </GameDataContext.Provider>
  );
};
