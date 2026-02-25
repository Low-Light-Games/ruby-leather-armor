import { useState, useEffect, useRef, useMemo, useCallback } from 'react'
import { AttributeRow } from './components/AttributeRow'
import { NameField } from './components/NameField'
import FlashMessage from '../FlashMessage'
import { useSheetsContext } from '../../contexts/SheetsContext'
import { Sheet, AttributeType } from '../../types'
import { PATHFINDER_RACES, getRaceById } from '../../rules/pathfinder_races'
import { PATHFINDER_CLASSES } from '../../rules/pathfinder_classes'

const AVAILABLE_POINTS = 27;

const POINT_COSTS: Record<number, number> = {
  7: -4, 8: -2, 9: -1, 10: 0, 11: 1, 12: 2,
  13: 3, 14: 5, 15: 7, 16: 10, 17: 13, 18: 17,
};

const ATTRIBUTES: AttributeType[] = ['strength', 'dexterity', 'constitution', 'intelligence', 'wisdom', 'charisma'];

const ABILITY_ABBR: Record<string, string> = {
  strength: 'STR',
  dexterity: 'DEX',
  constitution: 'CON',
  intelligence: 'INT',
  wisdom: 'WIS',
  charisma: 'CHA',
};

const DEFAULT_ATTRIBUTES: Record<AttributeType, number> = {
  strength: 10,
  intelligence: 10,
  dexterity: 10,
  constitution: 10,
  wisdom: 10,
  charisma: 10,
}

export const SheetEditor = () => {
  const {
    sheets, setSheets, sheetToEdit, setSheetToEdit,
    currentAttributes: attributes, setCurrentAttributes: setAttributes,
    racialModifiers,
    currentRace, setCurrentRace,
    currentFlexibleBonus, setCurrentFlexibleBonus,
    currentClass, setCurrentClass,
    currentLevel, setCurrentLevel,
    selectedFeats, setSelectedFeats,
    selectedSpells, setSelectedSpells,
  } = useSheetsContext();

  const [name, setName] = useState('')
  const [description, setDescription] = useState('')
  const [feedback, setFeedback] = useState<{ type: 'success' | 'error'; message: string } | null>(null)
  const [currentSheetId, setCurrentSheetId] = useState<number | null>(null)
  const [isPristine, setIsPristine] = useState(true)
  const csrfTokenRef = useRef<string | null>(null)

  // Point buy uses BASE scores only (racial modifiers don't affect cost)
  const spentPoints = useMemo(() => {
    return Object.values(attributes).reduce((total, value) => {
      return total + (POINT_COSTS[value] || 0)
    }, 0)
  }, [attributes])

  // Current race definition (for checking flexible bonus)
  const raceDefinition = useMemo(() => currentRace ? getRaceById(currentRace) : undefined, [currentRace])
  const hasFlexibleBonus = raceDefinition ? raceDefinition.flexibleBonusCount > 0 : false

  // Load sheet data when sheetToEdit changes
  useEffect(() => {
    if (sheetToEdit) {
      const hasChanges = !isPristine
      if (hasChanges) {
        const confirmed = window.confirm('You have unsaved changes. Are you sure you want to load this character? Your current changes will be lost.')
        if (!confirmed) {
          setSheetToEdit(null)
          return
        }
      }
      loadSheetForEdit(sheetToEdit)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sheetToEdit])

  // Track pristine state
  useEffect(() => {
    const pristine =
      name === '' &&
      description === '' &&
      JSON.stringify(attributes) === JSON.stringify(DEFAULT_ATTRIBUTES) &&
      currentSheetId === null &&
      currentRace === null &&
      currentFlexibleBonus === null &&
      currentClass === null &&
      currentLevel === 1 &&
      selectedFeats.length === 0 &&
      selectedSpells.length === 0
    setIsPristine(pristine)
  }, [name, description, attributes, currentSheetId, currentRace, currentFlexibleBonus, currentClass, currentLevel, selectedFeats, selectedSpells])

  const loadSheetForEdit = (sheet: Sheet) => {
    setName(sheet.name)
    setDescription(sheet.description || '')
    setAttributes({
      strength: sheet.strength,
      intelligence: sheet.intelligence,
      dexterity: sheet.dexterity,
      constitution: sheet.constitution,
      wisdom: sheet.wisdom,
      charisma: sheet.charisma,
    })
    setCurrentRace(sheet.race || null)
    setCurrentFlexibleBonus((sheet.racial_bonus_attribute as AttributeType) || null)
    setCurrentClass(sheet.character_class || null)
    setCurrentLevel(sheet.level || 1)
    setSelectedFeats(sheet.details?.feats || [])
    setSelectedSpells(sheet.details?.spells || [])
    setCurrentSheetId(sheet.id)
    setIsPristine(true)
    setSheetToEdit(null)
  }

  const resetToNew = () => {
    const hasChanges = !isPristine
    if (hasChanges) {
      const confirmed = window.confirm('You have unsaved changes. Are you sure you want to create a new character? Your current changes will be lost.')
      if (!confirmed) {
        return
      }
    }
    setName('')
    setDescription('')
    setAttributes(DEFAULT_ATTRIBUTES)
    setCurrentRace(null)
    setCurrentFlexibleBonus(null)
    setCurrentClass(null)
    setCurrentLevel(1)
    setSelectedFeats([])
    setSelectedSpells([])
    setCurrentSheetId(null)
    setSheetToEdit(null)
    setIsPristine(true)
  }

  const clearPoints = () => {
    setAttributes(DEFAULT_ATTRIBUTES)
  }

  const handleRaceChange = (raceId: string) => {
    const newRace = raceId || null
    setCurrentRace(newRace)
    // Reset flexible bonus when race changes
    setCurrentFlexibleBonus(null)
  }

  const handleClassChange = (classId: string) => {
    const newClass = classId || null
    setCurrentClass(newClass)
  }

  const saveSheet = async () => {
    try {
      const isUpdate = currentSheetId !== null
      const url = isUpdate ? `/sheets/${currentSheetId}` : '/sheets'
      const method = isUpdate ? 'PATCH' : 'POST'

      const response = await fetch(url, {
        method,
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfTokenRef.current || ''
        },
        body: JSON.stringify({
          sheet: {
            name,
            description: description.trim() || null,
            race: currentRace,
            racial_bonus_attribute: currentFlexibleBonus,
            character_class: currentClass,
            level: currentLevel,
            feat_ids: selectedFeats,
            spell_ids: selectedSpells,
            ...attributes
          }
        })
      })

      if (!response.ok) {
        const errorData = await response.json().catch(() => ({}))
        throw new Error(errorData.errors?.join(', ') || `HTTP error! status: ${response.status}`)
      }

      const savedSheet: Sheet = await response.json()
      setFeedback({ type: 'success', message: isUpdate ? 'Sheet updated successfully' : 'Sheet saved successfully' })

      if (isUpdate) {
        setSheets(sheets.map(s => s.id === savedSheet.id ? savedSheet : s))
      } else {
        setSheets([...sheets, savedSheet])
      }

      // Reset form to new character mode
      resetToNew()
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Error saving sheet'
      setFeedback({ type: 'error', message })
    }
  }

  useEffect(() => {
    csrfTokenRef.current = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || null
  }, [])

  const dismissFeedback = useCallback(() => setFeedback(null), [])

  const canIncrease = useCallback((attribute: AttributeType): boolean => {
    const currentValue = attributes[attribute]
    if (currentValue >= 18) return false

    const newValue = currentValue + 1
    const currentCost = POINT_COSTS[currentValue] || 0
    const newCost = POINT_COSTS[newValue] || 0
    const costDifference = newCost - currentCost

    return spentPoints + costDifference <= AVAILABLE_POINTS
  }, [attributes, spentPoints])

  const canDecrease = useCallback((attribute: AttributeType): boolean => {
    return attributes[attribute] > 7
  }, [attributes])

  const changeAttribute = useCallback((
    attribute: AttributeType,
    operation: 'increase' | 'decrease'
  ) => {
    if (operation === 'increase' && !canIncrease(attribute)) {
      return
    }
    if (operation === 'decrease' && !canDecrease(attribute)) {
      return
    }

    const delta = operation === 'increase' ? 1 : -1

    setAttributes(prev => ({
      ...prev,
      [attribute]: prev[attribute] + delta
    }))
  }, [canIncrease, canDecrease])

  return (
    <div>
      {feedback && (
        <FlashMessage
          type={feedback.type}
          message={feedback.message}
          onDismiss={dismissFeedback}
        />
      )}
      <h2>Points spent: {spentPoints} / {AVAILABLE_POINTS}</h2>

      <div className="form-field">
        <label htmlFor="character-name">Character Name:</label>
        <NameField name={name} onChange={setName} />
      </div>
      <div className="form-field">
        <label htmlFor="character-description">Character Description (optional):</label>
        <textarea
          id="character-description"
          value={description}
          onChange={e => setDescription(e.target.value)}
          rows={3}
          placeholder="Describe your character..."
        />
      </div>

      {/* Race selector */}
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

      {/* Flexible racial bonus selector */}
      {hasFlexibleBonus && (
        <div className="form-field">
          <label htmlFor="flex-bonus-select">
            Racial Bonus (+2 to one ability):
          </label>
          <select
            id="flex-bonus-select"
            value={currentFlexibleBonus || ''}
            onChange={e => setCurrentFlexibleBonus((e.target.value as AttributeType) || null)}
          >
            <option value="">— Choose Ability —</option>
            {ATTRIBUTES.map(attr => (
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

      {/* Ability score rows */}
      {ATTRIBUTES.map((attribute) => (
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

      {/* Class selector */}
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
            const val = parseInt(e.target.value, 10)
            if (!isNaN(val) && val >= 1 && val <= 20) setCurrentLevel(val)
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
        <button onClick={clearPoints} type="button" disabled={JSON.stringify(attributes) === JSON.stringify(DEFAULT_ATTRIBUTES)}>
          Clear Points Bought
        </button>
      </div>
    </div>
  )
}
