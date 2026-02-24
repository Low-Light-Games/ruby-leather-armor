import { useState, useEffect, useRef, useMemo, useCallback } from 'react'
import { AttributeRow } from './components/AttributeRow'
import { NameField } from './components/NameField'
import { useSheetsContext } from '../../contexts/SheetsContext'
import { Sheet, AttributeType } from '../../types'

const AVAILABLE_POINTS = 27;

const POINT_COSTS: Record<number, number> = {
  7: -4, 8: -2, 9: -1, 10: 0, 11: 1, 12: 2,
  13: 3, 14: 5, 15: 7, 16: 10, 17: 13, 18: 17,
};

const ATTRIBUTES: AttributeType[] = ['strength', 'intelligence', 'dexterity', 'constitution', 'wisdom', 'charisma'];

const DEFAULT_ATTRIBUTES: Record<AttributeType, number> = {
  strength: 10,
  intelligence: 10,
  dexterity: 10,
  constitution: 10,
  wisdom: 10,
  charisma: 10,
}

export const SheetEditor = () => {
  const { sheets, setSheets, sheetToEdit, setSheetToEdit } = useSheetsContext();

  const [name, setName] = useState('')
  const [description, setDescription] = useState('')
  const [feedback, setFeedback] = useState<[string, string] | null>(null)
  const [attributes, setAttributes] = useState<Record<AttributeType, number>>(DEFAULT_ATTRIBUTES)
  const [currentSheetId, setCurrentSheetId] = useState<number | null>(null)
  const [isPristine, setIsPristine] = useState(true)
  const csrfTokenRef = useRef<string | null>(null)
  const feedbackTimeoutRef = useRef<number | null>(null)

  const spentPoints = useMemo(() => {
    return Object.values(attributes).reduce((total, value) => {
      return total + (POINT_COSTS[value] || 0)
    }, 0)
  }, [attributes])

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
      currentSheetId === null
    setIsPristine(pristine)
  }, [name, description, attributes, currentSheetId])

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
    setCurrentSheetId(sheet.id)
    setIsPristine(true)
    setSheetToEdit(null) // Clear after loading to prevent reload loops
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
    setCurrentSheetId(null)
    setSheetToEdit(null)
    setIsPristine(true)
  }

  const clearPoints = () => {
    setAttributes(DEFAULT_ATTRIBUTES)
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
            ...attributes 
          } 
        })
      })

      if (!response.ok) {
        const errorData = await response.json().catch(() => ({}))
        throw new Error(errorData.errors?.join(', ') || `HTTP error! status: ${response.status}`)
      }

      const savedSheet: Sheet = await response.json()
      setFeedback(['success', isUpdate ? 'Sheet updated successfully' : 'Sheet saved successfully'])
      
      if (isUpdate) {
        setSheets(sheets.map(s => s.id === savedSheet.id ? savedSheet : s))
      } else {
        setSheets([...sheets, savedSheet])
      }
      
      // Reset form to new character mode
      resetToNew()
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Error saving sheet'
      setFeedback(['error', message])
    }
  }
  
  useEffect(() => {
    csrfTokenRef.current = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || null
  }, [])

  useEffect(() => {
    if (feedback) {
      // Clear previous timeout
      if (feedbackTimeoutRef.current) {
        clearTimeout(feedbackTimeoutRef.current)
      }
      // Set new timeout to clear feedback after 5 seconds
      feedbackTimeoutRef.current = window.setTimeout(() => {
        setFeedback(null)
      }, 5000)
    }

    return () => {
      if (feedbackTimeoutRef.current) {
        clearTimeout(feedbackTimeoutRef.current)
      }
    }
  }, [feedback])

  const canIncrease = useCallback((attribute: AttributeType): boolean => {
    const currentValue = attributes[attribute]
    if (currentValue >= 18) return false // Max value reached
    
    const newValue = currentValue + 1
    const currentCost = POINT_COSTS[currentValue] || 0
    const newCost = POINT_COSTS[newValue] || 0
    const costDifference = newCost - currentCost
    
    return spentPoints + costDifference <= AVAILABLE_POINTS
  }, [attributes, spentPoints])

  const canDecrease = useCallback((attribute: AttributeType): boolean => {
    return attributes[attribute] > 7 // Min value is 7
  }, [attributes])

  const changeAttribute = useCallback((
    attribute: AttributeType,
    operation: 'increase' | 'decrease'
  ) => {
    // Prevent invalid operations
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
      {feedback && <p className={`feedback-${feedback[0]}`} role="alert">{feedback[1]}</p>}
      <h1>Points spent: {spentPoints} / {AVAILABLE_POINTS}</h1>
      <p>Character Name: <NameField name={name} onChange={setName} /></p>
      <p>
        <label htmlFor="character-description">Character Description (optional):</label>
        <br />
        <textarea
          id="character-description"
          value={description}
          onChange={e => setDescription(e.target.value)}
          rows={4}
          cols={50}
          placeholder="Describe your character..."
        />
      </p>
      {ATTRIBUTES.map((attribute) => (
        <AttributeRow 
          key={attribute}
          attribute={attribute} 
          value={attributes[attribute]} 
          onChange={changeAttribute}
          canIncrease={canIncrease(attribute)}
          canDecrease={canDecrease(attribute)}
        />
      ))}
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
