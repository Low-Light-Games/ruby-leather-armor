import React, { useState, useCallback, useEffect } from 'react';
import { useModal } from '../../../hooks/useModal';
import type {
  ItemDefinition,
  EquipmentSlot,
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

function formatGp(amount: number): string {
  return amount % 1 === 0 ? `${amount}` : amount.toFixed(2);
}

function slotLabel(slot: EquipmentSlot): string {
  const entry = EQUIPMENT_SLOTS.find(s => s.slot === slot);
  return entry ? entry.label : slot;
}

/** Picker header by item-type filter (must match type-filter option values). */
function equipmentPickerModalTitle(typeFilter: string): string {
  switch (typeFilter) {
    case 'armor':
      return 'Armor';
    case 'shield':
      return 'Shields';
    case 'weapon':
      return 'Weapons';
    case 'gear':
      return 'Gear';
    case 'ammunition':
      return 'Ammunition';
    default:
      return 'Equipment';
  }
}

// ── Props ────────────────────────────────────────────────────────

export interface EquipmentEncumbranceProps {
  totalWeight: number;
  encumbranceTier: EncumbranceTier;
  carryCapacity: CarryCapacity;
}

type EquipmentSectionProps = UseEquipmentResult & {
  currentClass: string | null;
  encumbrance: EquipmentEncumbranceProps;
  encumbranceCalculation: CombatStatCalculation;
};

// ── Component ────────────────────────────────────────────────────

export const EquipmentSection: React.FC<EquipmentSectionProps> = ({
  currentClass,
  search,
  setSearch,
  typeFilter,
  setTypeFilter,
  startingGold,
  totalCost,
  currentGpValue,
  remainingGp,
  setGoldGp,
  addItem,
  removeItem,
  toggleEquip,
  changeQuantity,
  filteredItems,
  selectedWithDefs,
  encumbrance,
  encumbranceCalculation,
}) => {
  const encGlossary = useModal<CombatGlossaryKey>();
  const [customGoldEditOpen, setCustomGoldEditOpen] = useState(false);
  const [customGoldDraft, setCustomGoldDraft] = useState('');

  const closeEncGlossary = encGlossary.close;
  const openEncGlossary = useCallback((key: CombatGlossaryKey) => encGlossary.open(key), [encGlossary.open]);

  useEffect(() => {
    setCustomGoldEditOpen(false);
  }, [currentClass]);

  const openCustomGoldEdit = useCallback(() => {
    setCustomGoldDraft(formatGp(currentGpValue));
    setCustomGoldEditOpen(true);
  }, [currentGpValue]);

  const saveCustomGold = useCallback(() => {
    const parsed = parseFloat(customGoldDraft.replace(',', '.'));
    setGoldGp(Number.isFinite(parsed) ? parsed : 0);
    setCustomGoldEditOpen(false);
  }, [customGoldDraft, setGoldGp]);

  const cancelCustomGold = useCallback(() => {
    setCustomGoldEditOpen(false);
  }, []);

  const spentAllGold =
    currentGpValue > 0 && remainingGp <= 0.001;
  const overBudget = remainingGp < -0.001;

  return (
    <div className="picker-section equipment-section">
      <EncumbranceBarPanel
        totalWeight={encumbrance.totalWeight}
        encumbranceTier={encumbrance.encumbranceTier}
        carryCapacity={encumbrance.carryCapacity}
        onOpenGlossary={openEncGlossary}
      />

      <CombatStatHelpModal
        activeKey={encGlossary.data}
        onClose={closeEncGlossary}
        calculation={
          encGlossary.data === 'encumbrance' ? encumbranceCalculation : undefined
        }
      />

      {/* ── Gold (class required) ── */}
      {!currentClass ? (
        <p className="gold-class-hint">Choose a class to calculate your gold.</p>
      ) : (
        <div className="gold-budget-block">
          <div className="gold-budget-row">
            <div className="gold-gp-label">
              <span>Gold (gp)</span>
              {customGoldEditOpen ? (
                <div className="gold-custom-edit">
                  <input
                    type="number"
                    className="gold-gp-input"
                    min={0}
                    step="any"
                    autoFocus
                    value={customGoldDraft}
                    onChange={e => setCustomGoldDraft(e.target.value)}
                    onKeyDown={e => {
                      if (e.key === 'Enter') saveCustomGold();
                      if (e.key === 'Escape') cancelCustomGold();
                    }}
                  />
                  <div className="gold-custom-edit-actions">
                    <button type="button" className="gold-custom-save-btn" onClick={saveCustomGold}>
                      Save
                    </button>
                    <button type="button" className="gold-custom-cancel-btn" onClick={cancelCustomGold}>
                      Cancel
                    </button>
                  </div>
                </div>
              ) : (
                <div className="gold-gp-readout-row">
                  <span className="gold-gp-readout">{formatGp(currentGpValue)} gp</span>
                  <button
                    type="button"
                    className="gold-own-starting-btn"
                    onClick={openCustomGoldEdit}
                  >
                    Set your own starting gold
                  </button>
                </div>
              )}
            </div>
          </div>
          <div className={`gold-usage${overBudget ? ' gold-usage--over' : ''}`}>
            <span className="gold-usage-fraction">
              {formatGp(totalCost)} / {formatGp(currentGpValue)} gp
            </span>
            {spentAllGold && <span className="gold-usage-note">You spent all your gold.</span>}
            {overBudget && (
              <span className="gold-usage-note gold-usage-note--warn">
                Equipment costs more than your gold.
              </span>
            )}
          </div>
        </div>
      )}

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
          modalTitle={equipmentPickerModalTitle(typeFilter)}
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
