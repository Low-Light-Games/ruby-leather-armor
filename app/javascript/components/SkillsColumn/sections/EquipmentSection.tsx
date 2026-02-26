import React, { useState, useMemo, useCallback } from 'react';
import type { OwnedItem, ItemDefinition, EquipmentSlot, Currency } from '../../../rules/pathfinder_items_types';
import {
  getItemById,
  getItemDefinitions,
  getStartingGold,
  computeItemsCost,
  EQUIPMENT_SLOTS,
  totalGpValue,
  currencyFromGold,
} from '../../../rules/pathfinder_items';

// ── Helpers ──────────────────────────────────────────────────────

const ITEM_TYPE_LABELS: Record<string, string> = {
  armor: 'Armor',
  shield: 'Shield',
  weapon: 'Weapon',
  gear: 'Gear',
  ammunition: 'Ammo',
  potion: 'Potion',
  wondrous: 'Wondrous',
};

const DENOM_ORDER: (keyof Currency)[] = ['platinum', 'gold', 'silver', 'copper'];
const DENOM_LABELS: Record<keyof Currency, string> = {
  platinum: 'pp',
  gold: 'gp',
  silver: 'sp',
  copper: 'cp',
};

function formatGp(amount: number): string {
  return amount % 1 === 0 ? `${amount}` : amount.toFixed(2);
}

function slotLabel(slot: EquipmentSlot): string {
  const entry = EQUIPMENT_SLOTS.find(s => s.slot === slot);
  return entry ? entry.label : slot;
}

// ── Props ────────────────────────────────────────────────────────

interface EquipmentSectionProps {
  selectedItems: OwnedItem[];
  setSelectedItems: React.Dispatch<React.SetStateAction<OwnedItem[]>>;
  currentCurrency: Currency;
  setCurrentCurrency: React.Dispatch<React.SetStateAction<Currency>>;
  currentClass: string | null;
}

// ── Component ────────────────────────────────────────────────────

export const EquipmentSection: React.FC<EquipmentSectionProps> = ({
  selectedItems,
  setSelectedItems,
  currentCurrency,
  setCurrentCurrency,
  currentClass,
}) => {
  const [search, setSearch] = useState('');
  const [typeFilter, setTypeFilter] = useState<string>('');

  // Starting gold for the current class (suggestion)
  const startingGold = useMemo(() => getStartingGold(currentClass), [currentClass]);

  // Total cost of all selected items (in gp)
  const totalCost = useMemo(() => computeItemsCost(selectedItems), [selectedItems]);

  // Current wealth in gold-piece equivalent
  const currentGpValue = totalGpValue(currentCurrency);
  const remainingGp = currentGpValue - totalCost;

  // ── Currency editing ──

  const setCurrencyDenom = useCallback((denom: keyof Currency, value: number) => {
    setCurrentCurrency(prev => ({ ...prev, [denom]: Math.max(0, value) }));
  }, [setCurrentCurrency]);

  // ── Item add / remove / equip / quantity ──

  const addItem = useCallback((itemId: string) => {
    setSelectedItems(prev => {
      const existing = prev.find(i => i.itemId === itemId && !i.equipped);
      if (existing) {
        // Increase quantity of the existing unequipped stack
        return prev.map(i =>
          i === existing ? { ...i, quantity: i.quantity + 1 } : i,
        );
      }
      return [...prev, { itemId, quantity: 1, equipped: false, slotOverride: null }];
    });
    setSearch('');
  }, [setSelectedItems]);

  const removeItem = useCallback((itemId: string) => {
    setSelectedItems(prev => prev.filter(i => i.itemId !== itemId));
  }, [setSelectedItems]);

  const toggleEquip = useCallback((itemId: string) => {
    setSelectedItems(prev =>
      prev.map(i => (i.itemId === itemId ? { ...i, equipped: !i.equipped } : i)),
    );
  }, [setSelectedItems]);

  const changeQuantity = useCallback((itemId: string, delta: number) => {
    setSelectedItems(prev =>
      prev
        .map(i => {
          if (i.itemId !== itemId) return i;
          const newQty = i.quantity + delta;
          return newQty > 0 ? { ...i, quantity: newQty } : i;
        })
        .filter(i => i.quantity > 0),
    );
  }, [setSelectedItems]);

  // ── Dropdown results ──

  const filteredItems = useMemo(() => {
    const term = search.toLowerCase().trim();
    if (!term) return [];

    let pool = getItemDefinitions();

    if (typeFilter) {
      pool = pool.filter(i => i.itemType === typeFilter);
    }

    return pool
      .filter(i =>
        i.name.toLowerCase().includes(term) ||
        i.itemType.includes(term) ||
        (i.weaponCategory?.includes(term) ?? false),
      )
      .slice(0, 12);
  }, [search, typeFilter]);

  // ── Selected items with resolved defs ──

  const selectedWithDefs = useMemo(
    () =>
      selectedItems
        .map(oi => ({ oi, def: getItemById(oi.itemId) }))
        .filter((x): x is { oi: OwnedItem; def: ItemDefinition } => x.def != null),
    [selectedItems],
  );

  // ── Use starting gold ──
  const applyStartingGold = useCallback(() => {
    setCurrentCurrency(currencyFromGold(startingGold));
  }, [startingGold, setCurrentCurrency]);

  return (
    <div className="picker-section equipment-section">
      {/* ── Currency management ── */}
      <div className="currency-row">
        {DENOM_ORDER.map(denom => (
          <label key={denom} className="currency-input-group">
            <input
              type="number"
              className="currency-input"
              min={0}
              value={currentCurrency[denom]}
              onChange={e => setCurrencyDenom(denom, parseInt(e.target.value, 10) || 0)}
            />
            <span className="currency-label">{DENOM_LABELS[denom]}</span>
          </label>
        ))}
        {startingGold > 0 && (
          <button
            type="button"
            className="starting-gold-btn"
            onClick={applyStartingGold}
            title={`Set currency to class average (${startingGold} gp)`}
          >
            Class avg: {startingGold} gp
          </button>
        )}
      </div>

      {/* ── Cost summary ── */}
      <div className="cost-summary">
        <span>Wealth: <strong>{formatGp(currentGpValue)} gp</strong></span>
        <span>Spent: <strong>{formatGp(totalCost)} gp</strong></span>
        <span className={remainingGp < 0 ? 'overspent' : ''}>
          Remaining: <strong>{formatGp(remainingGp)} gp</strong>
        </span>
      </div>

      {/* ── Selected items ── */}
      {selectedWithDefs.length > 0 ? (
        <div className="selected-items">
          {selectedWithDefs.map(({ oi, def }) => (
            <div
              key={oi.itemId}
              className={`selected-item equip-item ${oi.equipped ? 'item-equipped' : ''}`}
            >
              <div className="selected-item-header">
                {/* Equip toggle (only for equippable items) */}
                {def.slot !== 'none' && (
                  <button
                    type="button"
                    className={`equip-toggle ${oi.equipped ? 'equipped' : ''}`}
                    onClick={() => toggleEquip(oi.itemId)}
                    title={oi.equipped ? `Unequip (${slotLabel(def.slot)})` : `Equip → ${slotLabel(def.slot)}`}
                  >
                    {oi.equipped ? 'E' : '○'}
                  </button>
                )}

                <span className="item-name">{def.name}</span>

                <span className={`item-tag cat-${def.itemType}`}>
                  {ITEM_TYPE_LABELS[def.itemType] || def.itemType}
                </span>

                {/* Quantity */}
                <span className="item-qty-controls">
                  <button
                    type="button"
                    className="qty-btn"
                    onClick={() => changeQuantity(oi.itemId, -1)}
                    disabled={oi.quantity <= 1}
                  >
                    −
                  </button>
                  <span className="qty-value">{oi.quantity}</span>
                  <button
                    type="button"
                    className="qty-btn"
                    onClick={() => changeQuantity(oi.itemId, 1)}
                  >
                    +
                  </button>
                </span>

                <button
                  className="remove-btn"
                  onClick={() => removeItem(oi.itemId)}
                  title="Remove item"
                >
                  &times;
                </button>
              </div>

              <div className="selected-item-summary">
                {formatGp(def.costGp * oi.quantity)} gp · {def.weight * oi.quantity} lb
                {def.armorBonus > 0 && ` · AC +${def.armorBonus}`}
                {def.shieldBonus > 0 && ` · Shield +${def.shieldBonus}`}
                {def.damageDice && ` · ${def.damageDice}`}
                {oi.equipped && def.slot !== 'none' && (
                  <span className="equip-slot-badge">{slotLabel(def.slot)}</span>
                )}
              </div>
            </div>
          ))}
        </div>
      ) : (
        <p className="empty-text">No items. Search below to add equipment.</p>
      )}

      {/* ── Search + type filter ── */}
      <div className="equip-search-row">
        <select
          className="type-filter"
          value={typeFilter}
          onChange={e => setTypeFilter(e.target.value)}
        >
          <option value="">All types</option>
          <option value="armor">Armor</option>
          <option value="shield">Shield</option>
          <option value="weapon">Weapon</option>
          <option value="gear">Gear</option>
          <option value="ammunition">Ammo</option>
        </select>

        <div className="picker-search">
          <input
            type="text"
            placeholder="Search items…"
            value={search}
            onChange={e => setSearch(e.target.value)}
            className="picker-input"
          />
          {filteredItems.length > 0 && (
            <ul className="picker-dropdown">
              {filteredItems.map(item => {
                const tooExpensive = item.costGp > remainingGp;
                return (
                  <li
                    key={item.id}
                    className={`picker-option ${tooExpensive ? 'locked' : ''}`}
                    onClick={() => !tooExpensive && addItem(item.id)}
                  >
                    <div className="option-header">
                      {tooExpensive && <span className="lock-icon">💰</span>}
                      <span className="option-name">{item.name}</span>
                      <span className={`item-tag cat-${item.itemType}`}>
                        {ITEM_TYPE_LABELS[item.itemType] || item.itemType}
                      </span>
                      <span className="option-price">{formatGp(item.costGp)} gp</span>
                    </div>
                    <div className="option-summary">
                      {item.summary}
                      {item.weight > 0 && ` · ${item.weight} lb`}
                      {item.armorBonus > 0 && ` · AC +${item.armorBonus}`}
                      {item.shieldBonus > 0 && ` · Shield +${item.shieldBonus}`}
                      {item.damageDice && ` · ${item.damageDice} ${item.damageType || ''}`}
                    </div>
                  </li>
                );
              })}
            </ul>
          )}
        </div>
      </div>
    </div>
  );
};
