import { useState, useEffect, useCallback } from 'react';
import type { Adventure, DerivedStats } from '../../../types';

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

    fetch(`/adventures/${adventureId}.json`)
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

  const ds: DerivedStats | null = adventure?.adventure_sheet?.derived_stats ?? null;

  return { adventure, ds, loading, error, reload: loadAdventure, setAdventure };
}
