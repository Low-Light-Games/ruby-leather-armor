import { useState, useEffect, useCallback } from 'react'
import { useAuth } from '../../contexts/AuthContext'
import Navbar from '../Navbar'
import Login from '../Login'
import FlashMessage from '../FlashMessage'
import { StoryState } from '../../types'
import { apiFetch } from '../../utils/api'
import './AdminStoryEditor.scss'

interface AdminStoryEditorProps {
  mode: 'create' | 'edit'
  storyId?: number
}

interface StoryData {
  id: number
  title: string
  preview: string
  premise: string
  story_states: StoryState[]
}

export const AdminStoryEditor = ({ mode, storyId }: AdminStoryEditorProps) => {
  const { user, loading: authLoading } = useAuth()

  const [loading, setLoading] = useState(mode === 'edit')
  const [saving, setSaving] = useState(false)
  const [feedback, setFeedback] = useState<{ type: 'success' | 'error'; message: string } | null>(null)

  // Story fields
  const [title, setTitle] = useState('')
  const [preview, setPreview] = useState('')
  const [premise, setPremise] = useState('')
  const [storyStates, setStoryStates] = useState<StoryState[]>([])
  const [currentStoryId, setCurrentStoryId] = useState<number | undefined>(storyId)

  // Story state editor
  const [newStateDescription, setNewStateDescription] = useState('')
  const [editingStateId, setEditingStateId] = useState<number | null>(null)
  const [editingStateDescription, setEditingStateDescription] = useState('')

  // Load story for edit mode
  useEffect(() => {
    if (mode !== 'edit' || !storyId || !user?.admin) return

    const loadStory = async () => {
      try {
        setLoading(true)
        const data: StoryData = await apiFetch(`/admin/stories/${storyId}.json`)
        setTitle(data.title)
        setPreview(data.preview)
        setPremise(data.premise)
        setStoryStates(data.story_states)
      } catch (err: any) {
        showFeedback('error', err.message)
      } finally {
        setLoading(false)
      }
    }

    loadStory()
  }, [mode, storyId, user])

  const showFeedback = useCallback((type: 'success' | 'error', msg: string) => {
    setFeedback({ type, message: msg })
  }, [])
  const dismissFeedback = useCallback(() => setFeedback(null), [])

  // ---- Story Save ----

  const saveStory = async () => {
    setSaving(true)
    try {
      const payload = { story: { title, preview, premise } }

      if (mode === 'create' && !currentStoryId) {
        const data: StoryData = await apiFetch('/admin/stories', {
          method: 'POST',
          body: JSON.stringify(payload),
        })
        // Redirect to the edit page for the newly created story
        window.location.href = `/admin/stories/${data.id}`
        return
      }

      // Update existing
      const data: StoryData = await apiFetch(`/admin/stories/${currentStoryId}`, {
        method: 'PATCH',
        body: JSON.stringify(payload),
      })
      setTitle(data.title)
      setPreview(data.preview)
      setPremise(data.premise)
      setStoryStates(data.story_states)
      showFeedback('success', 'Story saved successfully')
    } catch (err: any) {
      showFeedback('error', err.message)
    } finally {
      setSaving(false)
    }
  }

  // ---- Story State CRUD ----

  const addState = async () => {
    if (!currentStoryId || !newStateDescription.trim()) return
    try {
      const payload = { story_state: { description: newStateDescription.trim() } }
      const data: StoryState = await apiFetch(
        `/admin/stories/${currentStoryId}/story_states`,
        { method: 'POST', body: JSON.stringify(payload) },
      )
      setStoryStates(prev => [...prev, data])
      setNewStateDescription('')
      showFeedback('success', 'Stage added')
    } catch (err: any) {
      showFeedback('error', err.message)
    }
  }

  const startEditState = (state: StoryState) => {
    setEditingStateId(state.id)
    setEditingStateDescription(state.description)
  }

  const cancelEditState = () => {
    setEditingStateId(null)
    setEditingStateDescription('')
  }

  const saveEditState = async () => {
    if (!currentStoryId || !editingStateId) return
    try {
      const payload = { story_state: { description: editingStateDescription.trim() } }
      const data: StoryState = await apiFetch(
        `/admin/stories/${currentStoryId}/story_states/${editingStateId}`,
        { method: 'PATCH', body: JSON.stringify(payload) },
      )
      setStoryStates(prev => prev.map(st => (st.id === data.id ? data : st)))
      setEditingStateId(null)
      showFeedback('success', 'Stage updated')
    } catch (err: any) {
      showFeedback('error', err.message)
    }
  }

  const archiveState = async (stateId: number) => {
    if (!currentStoryId) return
    if (!window.confirm('Archive this stage?')) return
    try {
      await apiFetch(
        `/admin/stories/${currentStoryId}/story_states/${stateId}`,
        { method: 'DELETE' },
      )
      setStoryStates(prev => prev.filter(st => st.id !== stateId))
      showFeedback('success', 'Stage archived')
    } catch (err: any) {
      showFeedback('error', err.message)
    }
  }

  const moveState = async (stateId: number, newPosition: number) => {
    if (!currentStoryId) return
    try {
      const data: StoryState[] = await apiFetch(
        `/admin/stories/${currentStoryId}/story_states/${stateId}/reorder`,
        { method: 'PATCH', body: JSON.stringify({ position: newPosition }) },
      )
      setStoryStates(data)
    } catch (err: any) {
      showFeedback('error', err.message)
    }
  }

  // ---- Render ----

  if (authLoading) return <div className="app">Loading...</div>
  if (!user) return <Login />
  if (!user.admin) {
    return (
      <div className="app">
        <Navbar />
        <p className="feedback-error">Admin access required.</p>
      </div>
    )
  }

  if (loading) {
    return (
      <div className="app">
        <Navbar />
        <p style={{ padding: '20px' }}>Loading story...</p>
      </div>
    )
  }

  const isNew = mode === 'create' && !currentStoryId
  const canSave = title.trim() && preview.trim() && premise.trim()

  return (
    <div className="app">
      <Navbar />

      <div className="admin-story-editor">
        <div className="editor-top">
          <a href="/admin/stories" className="back-link">← Back to Stories</a>
          <h1>{isNew ? 'New Story' : `Edit: ${title}`}</h1>
        </div>

        {feedback && (
          <FlashMessage
            type={feedback.type}
            message={feedback.message}
            onDismiss={dismissFeedback}
          />
        )}

        {/* Story fields */}
        <div className="form-field">
          <label htmlFor="story-title">Title</label>
          <input
            type="text"
            id="story-title"
            value={title}
            onChange={e => setTitle(e.target.value)}
            placeholder="Story title"
          />
        </div>

        <div className="form-field">
          <label htmlFor="story-preview">Preview (shown to players)</label>
          <textarea
            id="story-preview"
            value={preview}
            onChange={e => setPreview(e.target.value)}
            rows={3}
            placeholder="A brief teaser for the player..."
          />
        </div>

        <div className="form-field">
          <label htmlFor="story-premise">Premise (full story, admin only)</label>
          <textarea
            id="story-premise"
            value={premise}
            onChange={e => setPremise(e.target.value)}
            rows={6}
            placeholder="The full premise and plot details..."
          />
        </div>

        <div className="editor-actions">
          <button
            className="btn-save"
            onClick={saveStory}
            disabled={saving || !canSave}
          >
            {saving ? 'Saving...' : isNew ? 'Create Story' : 'Save Changes'}
          </button>
        </div>

        {/* Story States (only when editing an existing story) */}
        {!isNew && (
          <div className="story-states-section">
            <h2>Stages ({storyStates.length})</h2>

            {storyStates.length === 0 ? (
              <p className="empty-msg">No stages yet. Add the first one below.</p>
            ) : (
              <ul className="states-list">
                {storyStates.map((state, idx) => (
                  <li key={state.id} className="state-item">
                    <div className="state-header">
                      <span className="state-position">#{idx + 1}</span>
                      <div className="state-reorder">
                        <button
                          disabled={idx === 0}
                          onClick={() => moveState(state.id, state.position - 1)}
                          title="Move up"
                        >▲</button>
                        <button
                          disabled={idx === storyStates.length - 1}
                          onClick={() => moveState(state.id, state.position + 1)}
                          title="Move down"
                        >▼</button>
                      </div>
                      <div className="state-actions">
                        {editingStateId === state.id ? (
                          <>
                            <button className="btn-sm save" onClick={saveEditState}>✓</button>
                            <button className="btn-sm cancel" onClick={cancelEditState}>✕</button>
                          </>
                        ) : (
                          <>
                            <button className="btn-sm edit" onClick={() => startEditState(state)} title="Edit">✏️</button>
                            <button className="btn-sm archive" onClick={() => archiveState(state.id)} title="Archive">🗑️</button>
                          </>
                        )}
                      </div>
                    </div>
                    {editingStateId === state.id ? (
                      <textarea
                        className="state-edit-textarea"
                        value={editingStateDescription}
                        onChange={e => setEditingStateDescription(e.target.value)}
                        rows={3}
                      />
                    ) : (
                      <p className="state-description">{state.description}</p>
                    )}
                  </li>
                ))}
              </ul>
            )}

            <div className="add-state">
              <textarea
                value={newStateDescription}
                onChange={e => setNewStateDescription(e.target.value)}
                rows={2}
                placeholder="Describe the new stage..."
              />
              <button
                className="btn-add-state"
                onClick={addState}
                disabled={!newStateDescription.trim()}
              >+ Add Stage</button>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}

export default AdminStoryEditor
