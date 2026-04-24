import { useState } from 'react'
import { useAuth } from '../../contexts/AuthContext'
import Navbar from '../Navbar'
import Login from '../Login'
import OnboardingWizard from '../OnboardingWizard'
import { useAdventureCreationData } from './hooks/useAdventureCreationData'
import { canAccessPaidAdventureOptions } from '../../utils/planAccess'
import AdventureList from './AdventureList'
import './AdventureCreation.scss'

export const AdventureCreation = () => {
  const { user, loading: authLoading } = useAuth()

  const {
    stories, sheets, adventures,
    loadingData, submitting, error, waitMessage,
    submitAdventure, deleteAdventure,
  } = useAdventureCreationData(user)

  const [selectedStoryId, setSelectedStoryId] = useState<number | ''>('')
  const [selectedSheetId, setSelectedSheetId] = useState<number | ''>('')
  const [directedDm, setDirectedDm] = useState(false)
  const [skipWorldSanityCheck, setSkipWorldSanityCheck] = useState(true)

  const selectedStory = stories.find(s => s.id === selectedStoryId) || null
  const selectedSheet = sheets.find(s => s.id === selectedSheetId) || null

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (!selectedStoryId || !selectedSheetId) return
    submitAdventure(selectedStoryId as number, selectedSheetId as number, directedDm, skipWorldSanityCheck)
  }

  if (authLoading) return <div className="app">Loading...</div>
  if (!user) return <Login />
  if (user.onboarding_state === 'new') {
    return (
      <div className="app">
        <Navbar />
        <OnboardingWizard />
      </div>
    )
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
                  disabled={sheets.length === 0}
                >
                  <option value="">-- Select a character --</option>
                  {sheets.map(sheet => (
                    <option key={sheet.id} value={sheet.id}>{sheet.name}</option>
                  ))}
                </select>
                {sheets.length === 0 && canAccessPaidAdventureOptions(user) && (
                  <p className="form-hint">
                    You do not have any saved custom characters yet. <a href="/sheets">Open the builder</a> to create one.
                  </p>
                )}
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

              <div className="form-group">
                <label className="toggle-row" htmlFor="directed-dm-toggle">
                  <span className="toggle-text">
                    <span className="toggle-label">Directed Play</span>
                      <span className="toggle-desc">At the end of each turn the GM prompts you with 2–3 concrete choices, guiding the adventure like a Choose Your Own Adventure game</span>
                  </span>
                  <span className={`toggle-switch ${directedDm ? 'active' : ''}`} role="switch" aria-checked={directedDm}>
                    <input
                      id="directed-dm-toggle"
                      type="checkbox"
                      checked={directedDm}
                      onChange={e => setDirectedDm(e.target.checked)}
                    />
                    <span className="toggle-track">
                      <span className="toggle-knob" />
                    </span>
                  </span>
                </label>
              </div>

              {canAccessPaidAdventureOptions(user) && (
                <div className="form-group">
                  <label className="toggle-row" htmlFor="skip-world-sanity-check-toggle">
                    <span className="toggle-text">
                      <span className="toggle-label">Skip World Sanity Check</span>
                      <span className="toggle-desc">Temporarily enabled by default while we smooth out world consistency issues. Turn it off if you want stricter scene validation.</span>
                    </span>
                    <span className={`toggle-switch ${skipWorldSanityCheck ? 'active' : ''}`} role="switch" aria-checked={skipWorldSanityCheck}>
                      <input
                        id="skip-world-sanity-check-toggle"
                        type="checkbox"
                        checked={skipWorldSanityCheck}
                        onChange={e => setSkipWorldSanityCheck(e.target.checked)}
                      />
                      <span className="toggle-track">
                        <span className="toggle-knob" />
                      </span>
                    </span>
                  </label>
                </div>
              )}

              {selectedSheet && (
                <div className="character-preview">
                  <h2>{selectedSheet.name} <small>(Lv {selectedSheet.level})</small></h2>
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
                {submitting ? 'Preparing your adventure...' : 'Begin Adventure'}
              </button>

              {submitting && waitMessage && (
                <p className="wait-message">{waitMessage}</p>
              )}
            </form>
          )}
        </div>

        <AdventureList
          adventures={adventures}
          loading={loadingData}
          onDelete={deleteAdventure}
        />
      </div>
    </div>
  )
}

export default AdventureCreation
