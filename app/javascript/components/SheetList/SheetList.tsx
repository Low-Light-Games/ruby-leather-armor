import { useEffect, useState } from "react"
import { useSheetsContext } from "../../contexts/SheetsContext"
import { Sheet } from "../../types"

export const SheetList = () => {
  const { sheets, setSheets } = useSheetsContext()
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    setLoading(true)
    setError(null)
    
    fetch('sheets')
      .then(response => {
        if (!response.ok) {
          if (response.status === 401) {
            throw new Error('Please log in to view your character sheets')
          }
          throw new Error(`HTTP error! status: ${response.status}`)
        }
        return response.json()
      })
      .then(data => {
        setSheets(data)
        setLoading(false)
      })
      .catch(error => {
        console.error('Error fetching characters:', error)
        setError(error.message || 'Failed to load character sheets')
        setLoading(false)
      })
  }, [setSheets])

  if (loading) {
    return <div>Loading...</div>
  }

  if (error) {
    return <div className="feedback-error">{error}</div>
  }

  return (
    <div>
      {sheets.length === 0 ? (
        <p>No character sheets yet. Create one to get started!</p>
      ) : (
        <ul>
          {sheets.map((character: Sheet) => (
            <li key={character.id}>{character.name}</li>
          ))}
        </ul>
      )}
    </div>
  )
}