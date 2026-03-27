/**
 * GameDataContext — fetches and caches feat/spell/item definitions from the API.
 *
 * Wrap any SPA root that needs game rule data in <GameDataProvider>.
 * Children won't render until feats, spells, and items have loaded.
 *
 * The loaded data is also pushed into the module-level caches inside
 * `pathfinder_feats.ts`, `pathfinder_spells.ts`, and `pathfinder_items.ts`
 * so that all helper functions (getFeatById, getSpellById, getItemById, etc.)
 * work unchanged.
 */

import React, { createContext, useContext, useEffect, useState, useMemo } from 'react';
import type { FeatDefinition } from '../rules/pathfinder_feats_types';
import type { SpellDefinition } from '../rules/pathfinder_spells_types';
import type { ItemDefinition } from '../rules/pathfinder_items_types';
import { setFeatDefinitions } from '../rules/pathfinder_feats';
import { routes } from '../utils/routes';
import { setSpellDefinitions } from '../rules/pathfinder_spells';
import { setItemDefinitions } from '../rules/pathfinder_items';

// ─── Context shape ──────────────────────────────────────────

interface GameDataContextValue {
  feats: FeatDefinition[];
  spells: SpellDefinition[];
  items: ItemDefinition[];
  loading: boolean;
  error: string | null;
}

const GameDataContext = createContext<GameDataContextValue>({
  feats: [],
  spells: [],
  items: [],
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
  const [items, setItems] = useState<ItemDefinition[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    const load = async () => {
      try {
        const [featsRes, spellsRes, itemsRes] = await Promise.all([
          fetch(`${routes.featDefinitions}.json`),
          fetch(`${routes.spellDefinitions}.json`),
          fetch(`${routes.itemDefinitions}.json`),
        ]);

        if (!featsRes.ok) throw new Error(`Feats fetch failed: ${featsRes.status}`);
        if (!spellsRes.ok) throw new Error(`Spells fetch failed: ${spellsRes.status}`);
        if (!itemsRes.ok) throw new Error(`Items fetch failed: ${itemsRes.status}`);

        const featsData: FeatDefinition[] = await featsRes.json();
        const spellsData: SpellDefinition[] = await spellsRes.json();
        const itemsData: ItemDefinition[] = await itemsRes.json();

        if (cancelled) return;

        // Push data into the module-level caches so helper functions work
        setFeatDefinitions(featsData);
        setSpellDefinitions(spellsData);
        setItemDefinitions(itemsData);

        setFeats(featsData);
        setSpells(spellsData);
        setItems(itemsData);
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
    () => ({ feats, spells, items, loading, error }),
    [feats, spells, items, loading, error],
  );

  return (
    <GameDataContext.Provider value={value}>
      {children}
    </GameDataContext.Provider>
  );
};
