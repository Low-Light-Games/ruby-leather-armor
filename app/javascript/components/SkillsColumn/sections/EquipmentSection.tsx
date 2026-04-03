import React, { useState, useCallback } from 'react';
import type {
  ItemDefinition,
  EquipmentSlot,
  Currency,
  CarryCapacity,
  EncumbranceTier,
} from '../../../rules/pathfinder_items_types';
import { EQUIPMENT_SLOTS } from '../../../rules/pathfinder_items';
import { Picker } from '../../ui/Picker';
import type { UseEquipmentResult } from '../hooks/useEquipment';
import type { CombatGlossaryKey } from '../combatGlossary/types';
import type { CombatStatCalculation } from '../combatHelp/combatCalcTypes';
import { EncumbranceBarPanel } from '../combatHelp/EncumbranceBarPanel';
import { CombatStatHelpModal } from '../combatHelp/CombatStatHelpModal';

// ── View helpers ─────────────────────────────────────────────────

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

export interface EquipmentEncumbranceProps {
  totalWeight: number;
  encumbranceTier: EncumbranceTier;
  carryCapacity: CarryCapacity;
}

type EquipmentSectionProps = UseEquipmentResult & {
  currentCurrency: Currency;
  encumbrance: EquipmentEncumbranceProps;
  encumbranceCalculation: CombatStatCalculation;
};

// ── Component ────────────────────────────────────────────────────

export const EquipmentSection: React.FC<EquipmentSectionProps> = ({
  currentCurrency,
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
  encumbrance,
  encumbranceCalculation,
}) => {
  const [encGlossaryKey, setEncGlossaryKey] = useState<CombatGlossaryKey | null>(null);
  const closeEncGlossary = useCallback(() => setEncGlossaryKey(null), []);
  const openEncGlossary = useCallback((key: CombatGlossaryKey) => setEncGlossaryKey(key), []);

  return (
    <div className="picker-section equipment-section">
      <EncumbranceBarPanel
        totalWeight={encumbrance.totalWeight}
        encumbranceTier={encumbrance.encumbranceTier}
        carryCapacity={encumbrance.carryCapacity}
        onOpenGlossary={openEncGlossary}
      />

      <CombatStatHelpModal
        activeKey={encGlossaryKey}
        onClose={closeEncGlossary}
        calculation={
          encGlossaryKey === 'encumbrance' ? encumbranceCalculation : undefined
        }
      />

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
                {def.slot !== 'none' && (
                  <button
                    type="button"
                    className={`equip-toggle ${oi.equipped ? 'equipped' : ''}`}
                    onClick={() => toggleEquip(oi.itemId)}
                    title={oi.equipped ? `Unequip (${slotLabel(def.slot)})` : `Equip → ${slotLabel(def.slot)}`}
                  >
                    {oi.equipped ? 'Equipped' : 'Equip'}
                  </button>
                )}

                <span className="item-name">{def.name}</span>

                <span className={`item-tag cat-${def.itemType}`}>
                  {ITEM_TYPE_LABELS[def.itemType] || def.itemType}
                </span>

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
        <Picker<ItemDefinition>
          search={search}
          onSearchChange={setSearch}
          placeholder="Search items…"
          items={filteredItems}
          itemKey={item => item.id}
          isDisabled={item => item.costGp > remainingGp}
          onSelect={item => addItem(item.id)}
          before={
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
          }
          renderOption={item => {
            const tooExpensive = item.costGp > remainingGp;
            return (
              <>
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
              </>
            );
          }}
        />
      </div>
    </div>
  );
};
