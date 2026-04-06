import { useMemo, useEffect } from 'react'
import { AttributeRow } from './components/AttributeRow'
import { NameField } from './components/NameField'
import FlashMessage from '../FlashMessage'
import { useSheetsContext } from '../../contexts/SheetsContext'
import { AttributeType } from '../../types'
import { ABILITY_ABBR, ATTRIBUTE_ORDER } from '../../utils/formatting'
import { PATHFINDER_RACES, getRaceById } from '../../rules/pathfinder_races'
import { PATHFINDER_CLASSES } from '../../rules/pathfinder_classes'
import { usePointBuy, AVAILABLE_POINTS } from './hooks/usePointBuy'
import { useSheetPersistence } from './hooks/useSheetPersistence'

export const SheetEditor = () => {
  const ctx = useSheetsContext();
  const {
    currentAttributes: attributes, setCurrentAttributes: setAttributes,
    racialModifiers,
    currentRace, setCurrentRace,
    currentFlexibleBonus, setCurrentFlexibleBonus,
    currentClass, setCurrentClass,
    currentLevel, setCurrentLevel,
    registerSheetDirtySource,
    syncSheetPristine,
    markSheetDirty,
  } = ctx;

  // ── Hooks ──────────────────────────────────────────────────────

  const persistence = useSheetPersistence(ctx);
  const {
    name, setName, description, setDescription,
    currentSheetId, feedback, dismissFeedback,
    saveSheet, resetToNew, setDirty, isPristine,
  } = persistence;

  useEffect(() => {
    registerSheetDirtySource(setDirty);
    return () => registerSheetDirtySource(null);
  }, [registerSheetDirtySource, setDirty]);

  useEffect(() => {
    syncSheetPristine(isPristine);
  }, [syncSheetPristine, isPristine]);

  const pointBuy = usePointBuy({ attributes, setAttributes, onDirty: setDirty });
  const { spentPoints, canIncrease, canDecrease, changeAttribute, clearPoints, isDefault } = pointBuy;

  // ── Derived ────────────────────────────────────────────────────

  const raceDefinition = useMemo(
    () => (currentRace ? getRaceById(currentRace) : undefined),
    [currentRace],
  );
  const hasFlexibleBonus = raceDefinition ? raceDefinition.flexibleBonusCount > 0 : false;

  // ── Handlers ───────────────────────────────────────────────────

  const handleRaceChange = (raceId: string) => {
    setDirty();
    setCurrentRace(raceId || null);
    setCurrentFlexibleBonus(null);
  };

  const handleClassChange = (classId: string) => {
    setDirty();
    setCurrentClass(classId || null);
  };

  // ── Render ─────────────────────────────────────────────────────

  return (
    <div>
      {feedback && (
        <FlashMessage
          type={feedback.type}
          message={feedback.message}
          onDismiss={dismissFeedback}
        />
      )}
      <div className="form-field">
        <label htmlFor="character-name">Character Name:</label>
        <NameField
          name={name}
          onChange={v => {
            markSheetDirty();
            setName(v);
          }}
        />
      </div>
      <div className="form-field">
        <label htmlFor="character-description">Character Description (optional):</label>
        <textarea
          id="character-description"
          value={description}
          onChange={e => {
            markSheetDirty();
            setDescription(e.target.value);
          }}
          rows={3}
          placeholder="Describe your character..."
        />
      </div>

      <div className="sheet-race-class-row">
        <div className="form-field">
          <label htmlFor="race-select">Race:</label>
          <select
            id="race-select"
            value={currentRace || ''}
            onChange={e => handleRaceChange(e.target.value)}
          >
            <option value="">— Select Race —</option>
            {PATHFINDER_RACES.map(r => (
              <option key={r.id} value={r.id}>{r.name}</option>
            ))}
          </select>
        </div>
        <div className="form-field">
          <label htmlFor="class-select">Class:</label>
          <select
            id="class-select"
            value={currentClass || ''}
            onChange={e => handleClassChange(e.target.value)}
          >
            <option value="">— Select Class —</option>
            {PATHFINDER_CLASSES.map(c => (
              <option key={c.id} value={c.id}>
                {c.name} (d{c.hitDie})
              </option>
            ))}
          </select>
        </div>
      </div>

      {/* Flexible racial bonus selector */}
      {hasFlexibleBonus && (
        <div className="form-field">
          <label htmlFor="flex-bonus-select">
            Racial Bonus (+2 to one ability):
          </label>
          <select
            id="flex-bonus-select"
            value={currentFlexibleBonus || ''}
            onChange={e => {
              markSheetDirty();
              setCurrentFlexibleBonus((e.target.value as AttributeType) || null);
            }}
          >
            <option value="">— Choose Ability —</option>
            {ATTRIBUTE_ORDER.map(attr => (
              <option key={attr} value={attr}>
                {attr.charAt(0).toUpperCase() + attr.slice(1)}
              </option>
            ))}
          </select>
        </div>
      )}

      {/* Race info summary */}
      {raceDefinition && (
        <div className="race-info">
          <span>Size: {raceDefinition.size}</span>
          <span>Speed: {raceDefinition.speed} ft.</span>
          {Object.entries(raceDefinition.fixedModifiers).length > 0 && (
            <span>
              Modifiers:{' '}
              {Object.entries(raceDefinition.fixedModifiers).map(([attr, val]) => {
                const v = val as number;
                return `${ABILITY_ABBR[attr] || attr} ${v > 0 ? '+' : ''}${v}`;
              }).join(', ')}
            </span>
          )}
        </div>
      )}
      <h3>Points spent: {spentPoints} / {AVAILABLE_POINTS}</h3>
      {/* Ability score rows */}
      {ATTRIBUTE_ORDER.map(attribute => (
        <AttributeRow
          key={attribute}
          attribute={attribute}
          value={attributes[attribute]}
          racialModifier={racialModifiers[attribute]}
          onChange={changeAttribute}
          canIncrease={canIncrease(attribute)}
          canDecrease={canDecrease(attribute)}
        />
      ))}

      {/* Level selector */}
      <div className="form-field">
        <label htmlFor="level-select">Level:</label>
        <input
          id="level-select"
          type="number"
          min={1}
          max={20}
          value={currentLevel}
          onChange={e => {
            const val = parseInt(e.target.value, 10);
            if (!isNaN(val) && val >= 1 && val <= 20) {
              markSheetDirty();
              setCurrentLevel(val);
            }
          }}
        />
      </div>

      <div className="sheet-editor-actions">
        <button onClick={saveSheet} disabled={!name.trim()}>
          {currentSheetId ? 'Update Sheet' : 'Save Sheet'}
        </button>
        <button onClick={resetToNew} type="button">
          Create New Character
        </button>
        <button onClick={clearPoints} type="button" disabled={isDefault}>
          Clear Points Bought
        </button>
      </div>
    </div>
  )
}
