import React from 'react';
import type { SpellSlotSummary } from '../../../rules/pathfinder_spells';
import type { SelectedSpellEligibility, FilteredSpellWithChecks, CastingStyleLabel } from '../hooks/useSpells';
import { SpellSlotBar } from '../shared/SpellSlotBar';
import { CastingNotice } from '../shared/CastingNotice';
import { Picker } from '../../ui/Picker';

interface SpellsSectionProps {
  currentClass: string | null;
  classDef: { name?: string; spellcasting?: { ability: string } } | undefined;
  classCasts: boolean;
  castingUnlocked: boolean;
  castingStyle: CastingStyleLabel;
  classStartLevel: number | null;
  currentLevel: number;
  currentMaxSpellLevel: number;
  spellSlots: SpellSlotSummary[];
  selectedSpells: SelectedSpellEligibility[];
  filteredSpells: FilteredSpellWithChecks[];
  search: string;
  onSearchChange: (value: string) => void;
  onAddSpell: (spellId: string) => void;
  onRemoveSpell: (spellId: string) => void;
}

export const SpellsSection: React.FC<SpellsSectionProps> = ({
  currentClass,
  classDef,
  classCasts,
  castingUnlocked,
  castingStyle,
  classStartLevel,
  currentLevel,
  currentMaxSpellLevel,
  spellSlots,
  selectedSpells,
  filteredSpells,
  search,
  onSearchChange,
  onAddSpell,
  onRemoveSpell,
}) => {
  // Non-caster notice
  if (currentClass && !classCasts) {
    return (
      <CastingNotice
        type="no-casting"
        message={`${classDef?.name ?? 'This class'} cannot cast spells.`}
      />
    );
  }

  // Casting not yet unlocked
  if (currentClass && classCasts && !castingUnlocked) {
    return (
      <CastingNotice
        type="not-yet"
        message={`Spellcasting begins at level ${classStartLevel}. (Currently level ${currentLevel})`}
      />
    );
  }

  // Prepared full-list casters
  if (currentClass && castingStyle === 'prepared_list' && castingUnlocked) {
    return (
      <CastingNotice
        type="prepared-list"
        message={`${classDef?.name} knows all class spells automatically. Daily spell preparation will be available during adventures.`}
      />
    );
  }

  // Active spellcasting: spontaneous or spellbook
  const placeholder = castingStyle === 'spellbook'
    ? 'Add spells to spellbook…'
    : castingStyle === 'spontaneous'
    ? `Search ${classDef?.name || ''} spells…`
    : currentClass
    ? `Search ${classDef?.name || ''} spells…`
    : 'Search all spells…';

  const emptyMessage = castingStyle === 'spellbook'
    ? 'No spells in spellbook yet.'
    : castingStyle === 'spontaneous'
    ? 'No known spells yet.'
    : 'No spells selected.';

  const spellPickerModalTitle =
    castingStyle === 'spellbook'
      ? 'Spellbook'
      : castingStyle === 'spontaneous'
        ? classDef?.name
          ? `${classDef.name} spells`
          : 'Known spells'
        : 'Spells';

  return (
    <div className="picker-section">
      {!currentClass && (
        <p className="empty-text">No class selected — browsing all spells.</p>
      )}

      {/* Casting style description */}
      {currentClass && castingUnlocked && (
        <div className="casting-style-info">
          {castingStyle === 'spontaneous' && (
            <p className="style-desc">
              {classDef?.name} — spontaneous caster
              ({classDef?.spellcasting?.ability.toUpperCase()}).
              Select your limited known spells below.
            </p>
          )}
          {castingStyle === 'spellbook' && (
            <p className="style-desc">
              {classDef?.name} — spellbook caster (INT).
              Build your starting spellbook below.
              {currentMaxSpellLevel === 0 ? ' Cantrips are added automatically.' : ''}
            </p>
          )}
        </div>
      )}

      {/* Slot counters */}
      {spellSlots.length > 0 && <SpellSlotBar slots={spellSlots} />}

      {/* Selected spells — with eligibility warnings */}
      {selectedSpells.length > 0 ? (
        <div className="selected-items">
          {selectedSpells.map(({ spell, eligibility }) => {
            const lvl = eligibility.spellLevel ?? (currentClass ? spell.classLevels[currentClass.toLowerCase()] : Object.values(spell.classLevels)[0]);
            const warn = eligibility.status !== 'available';
            return (
              <div key={spell.id} className={`selected-item spell-selected ${warn ? 'spell-warning' : ''}`}>
                <div className="selected-item-header">
                  <span className="spell-level-badge">{lvl ?? '?'}</span>
                  <span className="item-name">{spell.name}</span>
                  <span className="item-tag school-tag">{spell.school}</span>
                  <button className="remove-btn" onClick={() => onRemoveSpell(spell.id)} title="Remove spell">&times;</button>
                </div>
                <div className="selected-item-summary">{spell.summary}</div>
                {warn && eligibility.reason && (
                  <div className="spell-eligibility-warn">⚠ {eligibility.reason}</div>
                )}
              </div>
            );
          })}
        </div>
      ) : (
        <p className="empty-text">{emptyMessage}</p>
      )}

      {/* Search / add */}
      <Picker<FilteredSpellWithChecks>
        modalTitle={spellPickerModalTitle}
        search={search}
        onSearchChange={onSearchChange}
        placeholder={placeholder}
        items={filteredSpells}
        itemKey={f => f.spell.id}
        isDisabled={f => !f.selectable}
        onSelect={f => onAddSpell(f.spell.id)}
        renderOption={({ spell, eligibility, selectable, slotReason }) => {
          const lvl = eligibility.spellLevel ?? '?';
          const reason = !selectable
            ? (slotReason || eligibility.reason || '')
            : '';
          return (
            <>
              <div className="option-header">
                {!selectable && <span className="lock-icon">🔒</span>}
                <span className={`spell-level-badge small ${!selectable ? 'badge-locked' : ''}`}>{lvl}</span>
                <span className="option-name">{spell.name}</span>
                <span className="item-tag school-tag">{spell.school}</span>
              </div>
              <div className="option-summary">{spell.summary}</div>
              {reason && (
                <div className="option-prereqs">
                  <span className="prereq-labels">
                    <span className="prereq-chip prereq-unmet">✗ {reason}</span>
                  </span>
                </div>
              )}
            </>
          );
        }}
      />
    </div>
  );
};
