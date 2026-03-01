import { useState, useCallback } from 'react';
import type { Adventure } from '../../../types';
import { csrfToken } from '../../../utils/api';

interface UseInventoryResult {
  toggleEquip: (itemId: string) => void;
  equipSaving: boolean;
  equipError: string | null;
}

export function useInventory(
  adventure: Adventure | null,
  setAdventure: React.Dispatch<React.SetStateAction<Adventure | null>>,
): UseInventoryResult {
  const [equipSaving, setEquipSaving] = useState(false);
  const [equipError, setEquipError] = useState<string | null>(null);

  const toggleEquip = useCallback(async (itemId: string) => {
    if (!adventure || equipSaving) return;
    setEquipSaving(true);
    setEquipError(null);

    try {
      const res = await fetch(`/adventures/${adventure.id}/adventure_sheet/toggle_equip`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken() },
        body: JSON.stringify({ item_id: itemId }),
      });

      if (res.ok) {
        const updatedSheet = await res.json();
        setAdventure(prev => prev ? { ...prev, adventure_sheet: updatedSheet } : prev);
      } else {
        const data = await res.json().catch(() => ({}));
        setEquipError(data.error || 'Failed to toggle equip');
      }
    } catch (e) {
      console.error('Failed to toggle equip:', e);
      setEquipError('Failed to toggle equip');
    } finally {
      setEquipSaving(false);
    }
  }, [adventure, equipSaving, setAdventure]);

  return { toggleEquip, equipSaving, equipError };
}
