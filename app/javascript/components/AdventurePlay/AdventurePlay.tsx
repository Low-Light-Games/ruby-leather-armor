import { useState, useEffect } from 'react'
import { useAuth } from '../../contexts/AuthContext'
import Navbar from '../Navbar'
import Login from '../Login'
import { Adventure } from '../../types'
import './AdventurePlay.scss'

interface AdventurePlayProps {
  adventureId: number
}

const ATTRIBUTE_LABELS = ['strength', 'intelligence', 'dexterity', 'constitution', 'wisdom', 'charisma'] as const

export const AdventurePlay = ({ adventureId }: AdventurePlayProps) => {
  const { user, loading: authLoading } = useAuth()

  const [adventure, setAdventure] = useState<Adventure | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!user) return

    fetch(`/adventures/${adventureId}.json`)
      .then(response => {
        if (!response.ok) throw new Error('Failed to load adventure')
        return response.json()
      })
      .then(data => {
        setAdventure(data)
        setLoading(false)
      })
      .catch(err => {
        console.error('Error loading adventure:', err)
        setError(err.message)
        setLoading(false)
      })
  }, [user, adventureId])

  if (authLoading) {
    return <div className="app">Loading...</div>
  }

  if (!user) {
    return <Login />
  }

  if (loading) {
    return (
      <div className="app">
        <Navbar />
        <p>Loading adventure...</p>
      </div>
    )
  }

  if (error || !adventure) {
    return (
      <div className="app">
        <Navbar />
        <p className="feedback-error">{error || 'Adventure not found'}</p>
      </div>
    )
  }

  const { sheet, story, story_state } = adventure

  return (
    <div className="app">
      <Navbar />
      <div className="adventure-play">
        <div className="adventure-column character-column">
          <h2>{sheet.name}</h2>
          <div className="attributes-list">
            {ATTRIBUTE_LABELS.map(attr => (
              <div key={attr} className="attribute-item">
                <span className="attr-label">{attr}</span>
                <span className="attr-value">{sheet[attr]}</span>
              </div>
            ))}
          </div>
          <div className="adventure-stats">
            <div className="stat-item">
              <span className="stat-label">Gold</span>
              <span className="stat-value">{adventure.character_gold}</span>
            </div>
          </div>
        </div>

        <div className="adventure-column middle-column">
          {/* Empty for now */}
        </div>

        <div className="adventure-column story-column">
          <h2>{story.title}</h2>
          <p className="story-stage">{story_state.description}</p>
        </div>
      </div>
    </div>
  )
}

export default AdventurePlay
