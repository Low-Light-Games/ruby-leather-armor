import { useState, useEffect, useCallback } from 'react'
import { useAuth } from '../../contexts/AuthContext'
import AdminNavbar from '../AdminNavbar/AdminNavbar'
import Login from '../Login'
import FlashMessage from '../FlashMessage'
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
  initial_context: string | null
  initial_summary: string | null
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
  const [initialContext, setInitialContext] = useState('')
  const [initialSummary, setInitialSummary] = useState('')
  const [currentStoryId, setCurrentStoryId] = useState<number | undefined>(storyId)

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
        setInitialContext(data.initial_context || '')
        setInitialSummary(data.initial_summary || '')
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
      const payload = { story: { title, preview, premise, initial_context: initialContext, initial_summary: initialSummary } }

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
      setInitialContext(data.initial_context || '')
      setInitialSummary(data.initial_summary || '')
      showFeedback('success', 'Story saved successfully')
    } catch (err: any) {
      showFeedback('error', err.message)
    } finally {
      setSaving(false)
    }
  }

  // ---- Render ----

  if (authLoading) return <div className="app">Loading...</div>
  if (!user) return <Login />
  if (!user.admin) {
    return (
      <div className="app">
        <AdminNavbar active="stories" />
        <p className="feedback-error">Admin access required.</p>
      </div>
    )
  }

  if (loading) {
    return (
      <div className="app">
        <AdminNavbar active="stories" />
        <p style={{ padding: '20px' }}>Loading story...</p>
      </div>
    )
  }

  const isNew = mode === 'create' && !currentStoryId
  const canSave = title.trim() && preview.trim() && premise.trim()

  return (
    <div className="app">
      <AdminNavbar active="stories" />

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

        <div className="form-field">
          <label htmlFor="story-initial-context">Initial Context (opening scene for new adventures)</label>
          <textarea
            id="story-initial-context"
            value={initialContext}
            onChange={e => setInitialContext(e.target.value)}
            rows={4}
            placeholder="Where is the player? What's happening? This seeds the adventure's immediate context..."
          />
        </div>

        <div className="form-field">
          <label htmlFor="story-initial-summary">Initial Summary (story-so-far seed for new adventures)</label>
          <textarea
            id="story-initial-summary"
            value={initialSummary}
            onChange={e => setInitialSummary(e.target.value)}
            rows={4}
            placeholder="A brief narrative summary of where the story begins. This seeds the adventure's macro context..."
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
      </div>
    </div>
  )
}

export default AdminStoryEditor
