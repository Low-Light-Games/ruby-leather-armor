import { useState, useEffect, useRef } from 'react'
import { AttributeRow } from './components/AttributeRow'
import { NameField } from './components/NameField'
import { useSheetsContext } from '../../contexts/SheetsContext'
import { Sheet, AttributeType } from '../../types'

export const SheetEditor = () => {
  const { sheets, setSheets } = useSheetsContext();

  const [name, setName] = useState('')
  const [feedback, setFeedback] = useState<[string, string] | null>(null)
  const [strength, setStrength] = useState(10)
  const [intelligence, setIntelligence] = useState(10)
  const [dexterity, setDexterity] = useState(10)
  const [constitution, setConstitution] = useState(10)
  const [wisdom, setWisdom] = useState(10)
  const [charisma, setCharisma] = useState(10)
  const [spentPoints, setSpentPoints] = useState(0)
  const csrfTokenRef = useRef<string | null>(null)

  const pointCosts: Record<number, number> = {
    7: -4, 8: -2, 9: -1, 10: 0, 11: 1, 12: 2,
    13: 3, 14: 5, 15: 7, 16: 10, 17: 13, 18: 17,
  };

  const updatePoints = () => {
    let totalSpent = 0
    totalSpent += pointCosts[strength]
    totalSpent += pointCosts[intelligence]
    totalSpent += pointCosts[dexterity]
    totalSpent += pointCosts[constitution]
    totalSpent += pointCosts[wisdom]
    totalSpent += pointCosts[charisma]
    setSpentPoints(totalSpent)
  }

  const saveSheet = () => {
    fetch('sheets', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': csrfTokenRef.current || ''
      },
      body: JSON.stringify({ sheet: { name, strength, intelligence, dexterity, constitution, wisdom, charisma } })
    })
    .then(response => {
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }
      return response.json()
    })
    .then((createdSheet: Sheet) => {
      setFeedback(['success', 'Sheet saved successfully'])
      setSheets([...sheets, createdSheet])
    })
    .catch(() => {
      setFeedback(['error', 'Error saving sheet'])
    })
  }
  
  useEffect(() => {
    csrfTokenRef.current = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || null
  }, [])

  useEffect(() => {
    updatePoints()
  }, [strength, intelligence, dexterity, constitution, wisdom, charisma])
  
  const changeAttribute = (
    attribute: AttributeType,
    operation: 'increase' | 'decrease'
  ) => {
    const delta = operation === 'increase' ? 1 : -1;

    switch (attribute) {
      case 'strength':
        setStrength(prevStrength => prevStrength + delta)
        break
      case 'intelligence':
        setIntelligence(prevIntelligence => prevIntelligence + delta)
        break
      case 'dexterity':
        setDexterity(prevDexterity => prevDexterity + delta)
        break
      case 'constitution':
        setConstitution(prevConstitution => prevConstitution + delta)
        break
      case 'wisdom':
        setWisdom(prevWisdom => prevWisdom + delta)
        break
      case 'charisma':
        setCharisma(prevCharisma => prevCharisma + delta)
        break
      default:
        console.log('Invalid attribute')
        break 
    }
  }

  return (
    <div>
      {feedback && <p className={`feedback-${feedback[0]}`}>{feedback[1]}</p>}
      <h1>Points spent: {spentPoints}</h1>
      <p>Character Name: <NameField name={name} onChange={setName} /></p>
      <AttributeRow attribute="strength" value={strength} onChange={changeAttribute} />
      <AttributeRow attribute="intelligence" value={intelligence} onChange={changeAttribute} />
      <AttributeRow attribute="dexterity" value={dexterity} onChange={changeAttribute} />
      <AttributeRow attribute="constitution" value={constitution} onChange={changeAttribute} />
      <AttributeRow attribute="wisdom" value={wisdom} onChange={changeAttribute} />
      <AttributeRow attribute="charisma" value={charisma} onChange={changeAttribute} />
      <p>
        <button onClick={saveSheet}>Save Sheet</button>
      </p>
    </div>
  )
}
