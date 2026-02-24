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

export const SheetEditor = () => {
  const { sheets, setSheets } = useSheetsContext();

  const [name, setName] = useState('')
  const [feedback, setFeedback] = useState<[string, string] | null>(null)
  const [attributes, setAttributes] = useState<Record<AttributeType, number>>({
    strength: 10,
    intelligence: 10,
    dexterity: 10,
    constitution: 10,
    wisdom: 10,
    charisma: 10,
  })
  const csrfTokenRef = useRef<string | null>(null)
  const feedbackTimeoutRef = useRef<number | null>(null)

  const spentPoints = useMemo(() => {
    return Object.values(attributes).reduce((total, value) => {
      return total + (POINT_COSTS[value] || 0)
    }, 0)
  }, [attributes])

  const saveSheet = async () => {
    try {
      const response = await fetch('sheets', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfTokenRef.current || ''
        },
        body: JSON.stringify({ 
          sheet: { 
            name, 
            ...attributes 
          } 
        })
      })

      if (!response.ok) {
        const errorData = await response.json().catch(() => ({}))
        throw new Error(errorData.errors?.join(', ') || `HTTP error! status: ${response.status}`)
      }

      const createdSheet: Sheet = await response.json()
      setFeedback(['success', 'Sheet saved successfully'])
      setSheets([...sheets, createdSheet])
      
      // Reset form
      setName('')
      setAttributes({
        strength: 10,
        intelligence: 10,
        dexterity: 10,
        constitution: 10,
        wisdom: 10,
        charisma: 10,
      })
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
      <p>
        <button onClick={saveSheet} disabled={!name.trim()}>Save Sheet</button>
      </p>
    </div>
  )
}
