import { useState, useMemo, useCallback } from 'react';
import type { Dispatch, SetStateAction } from 'react';
import type { OwnedItem, ItemDefinition, Currency } from '../../../rules/pathfinder_items_types';
import {
  getItemById,
  getItemDefinitions,
  getStartingGold,
  computeItemsCost,
  totalGpValue,
  currencyFromGold,
} from '../../../rules/pathfinder_items';

// ── Params & return type ─────────────────────────────────────────

interface UseEquipmentParams {
  selectedItems: OwnedItem[];
  setSelectedItems: Dispatch<SetStateAction<OwnedItem[]>>;
  currentCurrency: Currency;
  setCurrentCurrency: Dispatch<SetStateAction<Currency>>;
  currentClass: string | null;
}

export interface SelectedItemRow {
  oi: OwnedItem;
  def: ItemDefinition;
}

export interface UseEquipmentResult {
  // Search state
  search: string;
  setSearch: (v: string) => void;
  typeFilter: string;
  setTypeFilter: (v: string) => void;
  // Cost / wealth
  startingGold: number;
  totalCost: number;
  currentGpValue: number;
  remainingGp: number;
  // Currency editing
  setCurrencyDenom: (denom: keyof Currency, value: number) => void;
  applyStartingGold: () => void;
  // Item CRUD
  addItem: (itemId: string) => void;
  removeItem: (itemId: string) => void;
  toggleEquip: (itemId: string) => void;
  changeQuantity: (itemId: string, delta: number) => void;
  // Derived lists
  filteredItems: ItemDefinition[];
  selectedWithDefs: SelectedItemRow[];
}

// ── Hook ─────────────────────────────────────────────────────────

export function useEquipment({
  selectedItems,
  setSelectedItems,
  currentCurrency,
  setCurrentCurrency,
  currentClass,
}: UseEquipmentParams): UseEquipmentResult {
  const [search, setSearch] = useState('');
  const [typeFilter, setTypeFilter] = useState('');

  // ── Wealth / cost ──

  const startingGold = useMemo(() => getStartingGold(currentClass), [currentClass]);
  const totalCost = useMemo(() => computeItemsCost(selectedItems), [selectedItems]);
  const currentGpValue = totalGpValue(currentCurrency);
  const remainingGp = currentGpValue - totalCost;

  // ── Currency editing ──

  const setCurrencyDenom = useCallback(
    (denom: keyof Currency, value: number) => {
      setCurrentCurrency(prev => ({ ...prev, [denom]: Math.max(0, value) }));
    },
    [setCurrentCurrency],
  );

  const applyStartingGold = useCallback(() => {
    setCurrentCurrency(currencyFromGold(startingGold));
  }, [startingGold, setCurrentCurrency]);

  // ── Item CRUD ──

  const addItem = useCallback(
    (itemId: string) => {
      setSelectedItems(prev => {
        const existing = prev.find(i => i.itemId === itemId && !i.equipped);
        if (existing) {
          return prev.map(i =>
            i === existing ? { ...i, quantity: i.quantity + 1 } : i,
          );
        }
        return [...prev, { itemId, quantity: 1, equipped: false, slotOverride: null }];
      });
      setSearch('');
    },
    [setSelectedItems],
  );

  const removeItem = useCallback(
    (itemId: string) => {
      setSelectedItems(prev => prev.filter(i => i.itemId !== itemId));
    },
    [setSelectedItems],
  );

  const toggleEquip = useCallback(
    (itemId: string) => {
      setSelectedItems(prev =>
        prev.map(i => (i.itemId === itemId ? { ...i, equipped: !i.equipped } : i)),
      );
    },
    [setSelectedItems],
  );

  const changeQuantity = useCallback(
    (itemId: string, delta: number) => {
      setSelectedItems(prev =>
        prev
          .map(i => {
            if (i.itemId !== itemId) return i;
            const newQty = i.quantity + delta;
            return newQty > 0 ? { ...i, quantity: newQty } : i;
          })
          .filter(i => i.quantity > 0),
      );
    },
    [setSelectedItems],
  );

  // ── Dropdown search results ──

  const filteredItems = useMemo(() => {
    const term = search.toLowerCase().trim();

    let pool = getItemDefinitions();
    if (typeFilter) {
      pool = pool.filter(i => i.itemType === typeFilter);
    }
    if (term) {
      pool = pool.filter(
        i =>
          i.name.toLowerCase().includes(term) ||
          i.itemType.includes(term) ||
          (i.weaponCategory?.includes(term) ?? false) ||
          (i.summary?.toLowerCase().includes(term) ?? false),
      );
    }

    return pool.slice(0, 20);
    // getItemDefinitions() cache is filled after fetch; length must be a dep to avoid stale empty lists.
  }, [search, typeFilter, getItemDefinitions().length]);

  // ── Selected items with resolved definitions ──

  const selectedWithDefs = useMemo(
    () =>
      selectedItems
        .map(oi => ({ oi, def: getItemById(oi.itemId) }))
        .filter((x): x is SelectedItemRow => x.def != null),
    [selectedItems, getItemDefinitions().length],
  );

  return {
    search,
    setSearch,
    typeFilter,
    setTypeFilter,
    startingGold,
    totalCost,
    currentGpValue,
    remainingGp,
    setCurrencyDenom,
    applyStartingGold,
    addItem,
    removeItem,
    toggleEquip,
    changeQuantity,
    filteredItems,
    selectedWithDefs,
  };
}
