import { useEffect, useState } from "react"
import { useSheetsContext } from "../../contexts/SheetsContext"
import { Sheet } from "../../types"
import './SheetList.scss'

export const SheetList = () => {
  const { sheets, setSheets, setSheetToEdit } = useSheetsContext()
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    setLoading(true)
    setError(null)
    
    fetch('/sheets')
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

  const handleEdit = (sheet: Sheet) => {
    setSheetToEdit(sheet)
  }

  const handleDelete = async (sheet: Sheet) => {
    const confirmed = window.confirm(`Are you sure you want to delete "${sheet.name}"? This cannot be undone.`)
    if (!confirmed) return

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || ''

    try {
      const response = await fetch(`/sheets/${sheet.id}`, {
        method: 'DELETE',
        headers: { 'X-CSRF-Token': csrfToken },
      })

      if (!response.ok) {
        throw new Error(`Failed to delete: ${response.status}`)
      }

      setSheets(prev => prev.filter(s => s.id !== sheet.id))
    } catch (err: any) {
      console.error('Error deleting sheet:', err)
      alert(err.message || 'Failed to delete character sheet.')
    }
  }

  return (
    <div>
      {sheets.length === 0 ? (
        <p>No character sheets yet. Create one to get started!</p>
      ) : (
        <ul className="sheet-list">
          {sheets.map((character: Sheet) => (
            <li key={character.id} className="sheet-list-item">
              <span className="sheet-name">{character.name}</span>
              <div className="sheet-actions">
                <button 
                  onClick={() => handleEdit(character)}
                  className="icon-button edit-button"
                  type="button"
                  title="Edit character"
                  aria-label={`Edit ${character.name}`}
                >
                  ✏️
                </button>
                <button
                  onClick={() => handleDelete(character)}
                  className="icon-button delete-button"
                  type="button"
                  title="Delete character"
                  aria-label={`Delete ${character.name}`}
                >
                  🗑️
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}