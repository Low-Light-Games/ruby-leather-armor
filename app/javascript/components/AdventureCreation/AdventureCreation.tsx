import { useState, useEffect } from 'react'
import { useAuth } from '../../contexts/AuthContext'
import Navbar from '../Navbar'
import Login from '../Login'
import { Story, Sheet, AdventureSummary } from '../../types'
import './AdventureCreation.scss'

export const AdventureCreation = () => {
  const { user, loading: authLoading } = useAuth()

  const [stories, setStories] = useState<Story[]>([])
  const [sheets, setSheets] = useState<Sheet[]>([])
  const [adventures, setAdventures] = useState<AdventureSummary[]>([])
  const [selectedStoryId, setSelectedStoryId] = useState<number | ''>('')
  const [selectedSheetId, setSelectedSheetId] = useState<number | ''>('')
  const [loadingData, setLoadingData] = useState(true)
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!user) return

    Promise.all([
      fetch('/stories').then(r => r.json()),
      fetch('/sheets').then(r => r.json()),
      fetch('/adventures').then(r => r.json()),
    ])
      .then(([storiesData, sheetsData, adventuresData]) => {
        setStories(storiesData)
        setSheets(sheetsData)
        setAdventures(adventuresData)
        setLoadingData(false)
      })
      .catch(err => {
        console.error('Failed to load data:', err)
        setError('Failed to load data.')
        setLoadingData(false)
      })
  }, [user])

  const selectedStory = stories.find(s => s.id === selectedStoryId) || null
  const selectedSheet = sheets.find(s => s.id === selectedSheetId) || null

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!selectedStoryId || !selectedSheetId) return

    setSubmitting(true)
    setError(null)

    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || ''

      const response = await fetch('/adventures', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken,
        },
        body: JSON.stringify({
          story_id: selectedStoryId,
          sheet_id: selectedSheetId,
        }),
      })

      if (!response.ok) {
        const data = await response.json()
        throw new Error(data.error || data.errors?.join(', ') || 'Failed to create adventure')
      }

      const adventure = await response.json()
      window.location.href = `/adventures/${adventure.id}`
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Something went wrong')
      setSubmitting(false)
    }
  }

  const handleDelete = async (adventureId: number) => {
    if (!window.confirm('Are you sure you want to delete this adventure? This cannot be undone.')) return

    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || ''
      const response = await fetch(`/adventures/${adventureId}`, {
        method: 'DELETE',
        headers: { 'X-CSRF-Token': csrfToken },
      })

      if (!response.ok) throw new Error('Failed to delete adventure')

      setAdventures(prev => prev.filter(a => a.id !== adventureId))
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to delete adventure')
    }
  }

  const formatDate = (dateStr: string) => {
    const date = new Date(dateStr)
    return date.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' })
      + ' ' + date.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' })
  }

  if (authLoading) {
    return <div className="app">Loading...</div>
  }

  if (!user) {
    return <Login />
  }

  return (
    <div className="app">
      <Navbar />
      <div className="adventure-page-layout">
        <div className="adventure-creation">
          <h1>Start a New Adventure</h1>

          {error && <p className="feedback-error">{error}</p>}

          {loadingData ? (
            <p>Loading...</p>
          ) : (
            <form onSubmit={handleSubmit} className="adventure-form">
              <div className="form-group">
                <label htmlFor="sheet-select">Choose your Character</label>
                <select
                  id="sheet-select"
                  value={selectedSheetId}
                  onChange={e => setSelectedSheetId(e.target.value ? Number(e.target.value) : '')}
                  required
                >
                  <option value="">-- Select a character --</option>
                  {sheets.map(sheet => (
                    <option key={sheet.id} value={sheet.id}>{sheet.name}</option>
                  ))}
                </select>
              </div>

              <div className="form-group">
                <label htmlFor="story-select">Choose a Story</label>
                <select
                  id="story-select"
                  value={selectedStoryId}
                  onChange={e => setSelectedStoryId(e.target.value ? Number(e.target.value) : '')}
                  required
                >
                  <option value="">-- Select a story --</option>
                  {stories.map(story => (
                    <option key={story.id} value={story.id}>{story.title}</option>
                  ))}
                </select>
              </div>

              {selectedSheet && (
                <div className="character-preview">
                  <h2>{selectedSheet.name}</h2>
                  {selectedSheet.description ? (
                    <p>{selectedSheet.description}</p>
                  ) : (
                    <p className="no-description">No description available</p>
                  )}
                </div>
              )}

              {selectedStory && (
                <div className="story-preview">
                  <h2>{selectedStory.title}</h2>
                  <p>{selectedStory.preview}</p>
                </div>
              )}

              <button
                type="submit"
                className="submit-button"
                disabled={!selectedStoryId || !selectedSheetId || submitting}
              >
                {submitting ? 'Setting off...' : 'Begin Adventure'}
              </button>
            </form>
          )}
        </div>

        <div className="ongoing-adventures">
          <h1>Your Adventures</h1>
          {loadingData ? (
            <p>Loading...</p>
          ) : adventures.length === 0 ? (
            <p className="no-adventures">No adventures yet. Start one!</p>
          ) : (
            <ul className="adventure-list">
              {adventures.map(adv => (
                <li key={adv.id} className="adventure-list-item">
                  <a href={`/adventures/${adv.id}`} className="adventure-link">
                    <span className="adventure-character">{adv.character_name}</span>
                    <span className="adventure-story">{adv.story_title}</span>
                    <span className="adventure-meta">
                      <span className="adventure-gold">{adv.character_gold} gold</span>
                      <span className="adventure-date">Last played: {formatDate(adv.updated_at)}</span>
                    </span>
                  </a>
                  <button
                    className="adventure-delete"
                    type="button"
                    onClick={() => handleDelete(adv.id)}
                    title="Delete adventure"
                  >
                    &times;
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>
    </div>
  )
}

export default AdventureCreation
