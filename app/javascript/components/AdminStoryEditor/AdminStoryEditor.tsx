import { useState, useEffect, useCallback } from 'react'
import { useAuth } from '../../contexts/AuthContext'
import AdminNavbar from '../AdminNavbar/AdminNavbar'
import Login from '../Login'
import FlashMessage from '../FlashMessage'
import { apiFetch } from '../../utils/api'
import type { StoryLocationData, LocationConnectionData, EncounterTableData, EncounterTableEntryData } from '../../types'
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
  hook: string | null
  initial_context: string | null
  initial_summary: string | null
  story_locations?: StoryLocationData[]
  encounter_tables?: EncounterTableData[]
}

const TERRAIN_TYPES = ['road', 'trail', 'forest', 'mountain', 'swamp', 'desert', 'river', 'coast', 'urban', 'underground']

const emptyLocation = (): StoryLocationData => ({
  name: '', description: '', starting: false, connections_from: []
})

const emptyConnection = (): LocationConnectionData => ({
  to_location_id: 0, distance_miles: 1, terrain_type: 'road', description: ''
})

const emptyTable = (): EncounterTableData => ({
  name: '', description: '', check_frequency_hours: 4, encounter_chance: 15, encounter_table_entries: []
})

const emptyEntry = (): EncounterTableEntryData => ({
  title: '', description: '', entry_type: 'fixed', weight: 1
})

export const AdminStoryEditor = ({ mode, storyId }: AdminStoryEditorProps) => {
  const { user, loading: authLoading } = useAuth()

  const [loading, setLoading] = useState(mode === 'edit')
  const [saving, setSaving] = useState(false)
  const [feedback, setFeedback] = useState<{ type: 'success' | 'error'; message: string } | null>(null)

  const [title, setTitle] = useState('')
  const [preview, setPreview] = useState('')
  const [premise, setPremise] = useState('')
  const [hook, setHook] = useState('')
  const [initialContext, setInitialContext] = useState('')
  const [initialSummary, setInitialSummary] = useState('')
  const [currentStoryId, setCurrentStoryId] = useState<number | undefined>(storyId)

  const [locations, setLocations] = useState<StoryLocationData[]>([])
  const [encounterTables, setEncounterTables] = useState<EncounterTableData[]>([])

  const [locationsOpen, setLocationsOpen] = useState(false)
  const [encounterTablesOpen, setEncounterTablesOpen] = useState(false)
  const [expandedLocIdx, setExpandedLocIdx] = useState<number | null>(null)
  const [expandedTableIdx, setExpandedTableIdx] = useState<number | null>(null)

  useEffect(() => {
    if (mode !== 'edit' || !storyId || !user?.admin) return

    const loadStory = async () => {
      try {
        setLoading(true)
        const data: StoryData = await apiFetch(`/admin/stories/${storyId}.json`)
        setTitle(data.title)
        setPreview(data.preview)
        setPremise(data.premise)
        setHook(data.hook || '')
        setInitialContext(data.initial_context || '')
        setInitialSummary(data.initial_summary || '')
        setLocations(data.story_locations || [])
        setEncounterTables(data.encounter_tables || [])
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

  // ---- Build nested attributes payload ----

  const buildPayload = () => {
    const story: Record<string, unknown> = {
      title, preview, premise, hook,
      initial_context: initialContext,
      initial_summary: initialSummary,
    }

    if (currentStoryId) {
      story.story_locations_attributes = locations.map(loc => {
        const locAttrs: Record<string, unknown> = {
          name: loc.name, description: loc.description, starting: loc.starting,
        }
        if (loc.id) locAttrs.id = loc.id
        if (loc._destroy) locAttrs._destroy = true

        const savedLocs = locations.filter(l => l.id && !l._destroy)
        locAttrs.connections_from_attributes = (loc.connections_from || []).map(conn => {
          const connAttrs: Record<string, unknown> = {
            to_location_id: conn.to_location_id,
            distance_miles: conn.distance_miles,
            terrain_type: conn.terrain_type,
            description: conn.description || '',
          }
          if (conn.id) connAttrs.id = conn.id
          if (conn._destroy) connAttrs._destroy = true
          return connAttrs
        }).filter(c => c.to_location_id || c._destroy)

        return locAttrs
      })

      story.encounter_tables_attributes = encounterTables.map(table => {
        const tAttrs: Record<string, unknown> = {
          name: table.name, description: table.description,
          check_frequency_hours: table.check_frequency_hours,
          encounter_chance: table.encounter_chance,
        }
        if (table.id) tAttrs.id = table.id
        if (table._destroy) tAttrs._destroy = true

        tAttrs.encounter_table_entries_attributes = (table.encounter_table_entries || []).map(entry => {
          const eAttrs: Record<string, unknown> = {
            title: entry.title, description: entry.description,
            entry_type: entry.entry_type, weight: entry.weight,
            terrain_types: entry.terrain_types || '',
            min_party_level: entry.min_party_level,
            max_party_level: entry.max_party_level,
          }
          if (entry.id) eAttrs.id = entry.id
          if (entry._destroy) eAttrs._destroy = true
          return eAttrs
        })

        return tAttrs
      })
    }

    return { story }
  }

  const saveStory = async () => {
    setSaving(true)
    try {
      const payload = buildPayload()

      if (mode === 'create' && !currentStoryId) {
        const data: StoryData = await apiFetch('/admin/stories', {
          method: 'POST',
          body: JSON.stringify(payload),
        })
        window.location.href = `/admin/stories/${data.id}`
        return
      }

      const data: StoryData = await apiFetch(`/admin/stories/${currentStoryId}`, {
        method: 'PATCH',
        body: JSON.stringify(payload),
      })
      setTitle(data.title)
      setPreview(data.preview)
      setPremise(data.premise)
      setHook(data.hook || '')
      setInitialContext(data.initial_context || '')
      setInitialSummary(data.initial_summary || '')
      setLocations(data.story_locations || [])
      setEncounterTables(data.encounter_tables || [])
      showFeedback('success', 'Story saved successfully')
    } catch (err: any) {
      showFeedback('error', err.message)
    } finally {
      setSaving(false)
    }
  }

  // ---- Location helpers ----

  const updateLocation = (idx: number, patch: Partial<StoryLocationData>) => {
    setLocations(prev => prev.map((l, i) => i === idx ? { ...l, ...patch } : l))
  }

  const setStartingLocation = (idx: number) => {
    setLocations(prev => prev.map((l, i) => ({ ...l, starting: i === idx })))
  }

  const removeLocation = (idx: number) => {
    const loc = locations[idx]
    if (loc.id) {
      updateLocation(idx, { _destroy: true })
    } else {
      setLocations(prev => prev.filter((_, i) => i !== idx))
    }
  }

  const addConnection = (locIdx: number) => {
    setLocations(prev => prev.map((l, i) =>
      i === locIdx ? { ...l, connections_from: [...(l.connections_from || []), emptyConnection()] } : l
    ))
  }

  const updateConnection = (locIdx: number, connIdx: number, patch: Partial<LocationConnectionData>) => {
    setLocations(prev => prev.map((l, li) => {
      if (li !== locIdx) return l
      const conns = (l.connections_from || []).map((c, ci) =>
        ci === connIdx ? { ...c, ...patch } : c
      )
      return { ...l, connections_from: conns }
    }))
  }

  const removeConnection = (locIdx: number, connIdx: number) => {
    setLocations(prev => prev.map((l, li) => {
      if (li !== locIdx) return l
      const conn = (l.connections_from || [])[connIdx]
      if (conn?.id) {
        const conns = (l.connections_from || []).map((c, ci) =>
          ci === connIdx ? { ...c, _destroy: true } : c
        )
        return { ...l, connections_from: conns }
      }
      return { ...l, connections_from: (l.connections_from || []).filter((_, ci) => ci !== connIdx) }
    }))
  }

  // ---- Encounter table helpers ----

  const updateTable = (idx: number, patch: Partial<EncounterTableData>) => {
    setEncounterTables(prev => prev.map((t, i) => i === idx ? { ...t, ...patch } : t))
  }

  const removeTable = (idx: number) => {
    const table = encounterTables[idx]
    if (table.id) {
      updateTable(idx, { _destroy: true })
    } else {
      setEncounterTables(prev => prev.filter((_, i) => i !== idx))
    }
  }

  const addEntry = (tableIdx: number) => {
    setEncounterTables(prev => prev.map((t, i) =>
      i === tableIdx ? { ...t, encounter_table_entries: [...(t.encounter_table_entries || []), emptyEntry()] } : t
    ))
  }

  const updateEntry = (tableIdx: number, entryIdx: number, patch: Partial<EncounterTableEntryData>) => {
    setEncounterTables(prev => prev.map((t, ti) => {
      if (ti !== tableIdx) return t
      const entries = (t.encounter_table_entries || []).map((e, ei) =>
        ei === entryIdx ? { ...e, ...patch } : e
      )
      return { ...t, encounter_table_entries: entries }
    }))
  }

  const removeEntry = (tableIdx: number, entryIdx: number) => {
    setEncounterTables(prev => prev.map((t, ti) => {
      if (ti !== tableIdx) return t
      const entry = (t.encounter_table_entries || [])[entryIdx]
      if (entry?.id) {
        const entries = (t.encounter_table_entries || []).map((e, ei) =>
          ei === entryIdx ? { ...e, _destroy: true } : e
        )
        return { ...t, encounter_table_entries: entries }
      }
      return { ...t, encounter_table_entries: (t.encounter_table_entries || []).filter((_, ei) => ei !== entryIdx) }
    }))
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
  const isEditMode = !!currentStoryId
  const visibleLocations = locations.filter(l => !l._destroy)
  const savedLocations = locations.filter(l => l.id && !l._destroy)

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
          <input type="text" id="story-title" value={title}
            onChange={e => setTitle(e.target.value)} placeholder="Story title" />
        </div>

        <div className="form-field">
          <label htmlFor="story-preview">Preview (shown to players)</label>
          <textarea id="story-preview" value={preview}
            onChange={e => setPreview(e.target.value)} rows={3}
            placeholder="A brief teaser for the player..." />
        </div>

        <div className="form-field">
          <label htmlFor="story-premise">Premise (full story, admin only)</label>
          <textarea id="story-premise" value={premise}
            onChange={e => setPremise(e.target.value)} rows={6}
            placeholder="The full premise and plot details..." />
        </div>

        <div className="form-field">
          <label htmlFor="story-hook">Hook (spoiler-free player-facing intro)</label>
          <textarea id="story-hook" value={hook}
            onChange={e => setHook(e.target.value)} rows={4}
            placeholder="A spoiler-free description of the starting situation..." />
        </div>

        <div className="form-field">
          <label htmlFor="story-initial-context">Initial Context (opening scene)</label>
          <textarea id="story-initial-context" value={initialContext}
            onChange={e => setInitialContext(e.target.value)} rows={4}
            placeholder="Where is the player? What's happening?..." />
        </div>

        <div className="form-field">
          <label htmlFor="story-initial-summary">Initial Summary (story-so-far seed)</label>
          <textarea id="story-initial-summary" value={initialSummary}
            onChange={e => setInitialSummary(e.target.value)} rows={4}
            placeholder="A brief narrative summary of where the story begins..." />
        </div>

        {/* ---- Locations ---- */}
        {isEditMode && (
          <div className="collapsible-section">
            <button className="section-toggle" onClick={() => setLocationsOpen(!locationsOpen)}>
              <span className="toggle-icon">{locationsOpen ? '▾' : '▸'}</span>
              Locations ({visibleLocations.length})
            </button>

            {locationsOpen && (
              <div className="section-body">
                <p className="section-hint">
                  Define named locations for this story. Mark one as the starting location.
                  Connect locations with distances for travel resolution.
                </p>

                {visibleLocations.length === 0 && (
                  <p className="empty-hint">No locations yet.</p>
                )}

                {locations.map((loc, locIdx) => {
                  if (loc._destroy) return null
                  const isExpanded = expandedLocIdx === locIdx
                  const visibleConns = (loc.connections_from || []).filter(c => !c._destroy)
                  return (
                    <div key={loc.id || `new-${locIdx}`} className="nested-card">
                      <div className="nested-card-header">
                        <button className="expand-btn" onClick={() => setExpandedLocIdx(isExpanded ? null : locIdx)}>
                          {isExpanded ? '▾' : '▸'}
                        </button>
                        <input type="text" className="inline-name" value={loc.name}
                          onChange={e => updateLocation(locIdx, { name: e.target.value })}
                          placeholder="Location name" />
                        <label className="starting-label">
                          <input type="radio" name="starting-location"
                            checked={loc.starting}
                            onChange={() => setStartingLocation(locIdx)} />
                          Start
                        </label>
                        <button className="btn-remove" onClick={() => removeLocation(locIdx)}>✕</button>
                      </div>

                      {isExpanded && (
                        <div className="nested-card-body">
                          <textarea value={loc.description || ''} rows={2}
                            onChange={e => updateLocation(locIdx, { description: e.target.value })}
                            placeholder="Location description..." />

                          <div className="connections-section">
                            <strong>Connections</strong>
                            {visibleConns.length === 0 && <p className="empty-hint">No connections.</p>}
                            {(loc.connections_from || []).map((conn, connIdx) => {
                              if (conn._destroy) return null
                              return (
                                <div key={conn.id || `conn-${connIdx}`} className="connection-row">
                                  <select value={conn.to_location_id || ''}
                                    onChange={e => updateConnection(locIdx, connIdx, { to_location_id: Number(e.target.value) })}>
                                    <option value="">— destination —</option>
                                    {savedLocations.filter(sl => sl.id !== loc.id).map(sl => (
                                      <option key={sl.id} value={sl.id}>{sl.name || '(unnamed)'}</option>
                                    ))}
                                  </select>
                                  <input type="number" className="dist-input" value={conn.distance_miles}
                                    onChange={e => updateConnection(locIdx, connIdx, { distance_miles: Number(e.target.value) })}
                                    min={0.1} step={0.1} />
                                  <span className="unit">mi</span>
                                  <select value={conn.terrain_type}
                                    onChange={e => updateConnection(locIdx, connIdx, { terrain_type: e.target.value })}>
                                    {TERRAIN_TYPES.map(t => <option key={t} value={t}>{t}</option>)}
                                  </select>
                                  <button className="btn-remove-sm" onClick={() => removeConnection(locIdx, connIdx)}>✕</button>
                                </div>
                              )
                            })}
                            <button className="btn-add-sm" onClick={() => addConnection(locIdx)}>+ Connection</button>
                          </div>
                        </div>
                      )}
                    </div>
                  )
                })}

                <button className="btn-add" onClick={() => setLocations(prev => [...prev, emptyLocation()])}>
                  + Add Location
                </button>
              </div>
            )}
          </div>
        )}

        {/* ---- Encounter Tables ---- */}
        {isEditMode && (
          <div className="collapsible-section">
            <button className="section-toggle" onClick={() => setEncounterTablesOpen(!encounterTablesOpen)}>
              <span className="toggle-icon">{encounterTablesOpen ? '▾' : '▸'}</span>
              Encounter Tables ({encounterTables.filter(t => !t._destroy).length})
            </button>

            {encounterTablesOpen && (
              <div className="section-body">
                <p className="section-hint">
                  Define encounter tables for this story. Each table has a chance and frequency for random encounter checks.
                  Entries can be fixed text or AI-powered prompts.
                </p>

                {encounterTables.filter(t => !t._destroy).length === 0 && (
                  <p className="empty-hint">No encounter tables. A global default will be used if available.</p>
                )}

                {encounterTables.map((table, tableIdx) => {
                  if (table._destroy) return null
                  const isExpanded = expandedTableIdx === tableIdx
                  const visibleEntries = (table.encounter_table_entries || []).filter(e => !e._destroy)
                  return (
                    <div key={table.id || `table-${tableIdx}`} className="nested-card">
                      <div className="nested-card-header">
                        <button className="expand-btn" onClick={() => setExpandedTableIdx(isExpanded ? null : tableIdx)}>
                          {isExpanded ? '▾' : '▸'}
                        </button>
                        <input type="text" className="inline-name" value={table.name}
                          onChange={e => updateTable(tableIdx, { name: e.target.value })}
                          placeholder="Table name (e.g. Road Encounters)" />
                        <span className="table-meta">
                          {table.encounter_chance}% / {table.check_frequency_hours}h
                        </span>
                        <button className="btn-remove" onClick={() => removeTable(tableIdx)}>✕</button>
                      </div>

                      {isExpanded && (
                        <div className="nested-card-body">
                          <div className="table-config-row">
                            <div className="form-field compact">
                              <label>Chance (%)</label>
                              <input type="number" value={table.encounter_chance} min={0} max={100}
                                onChange={e => updateTable(tableIdx, { encounter_chance: Number(e.target.value) })} />
                            </div>
                            <div className="form-field compact">
                              <label>Frequency (hours)</label>
                              <input type="number" value={table.check_frequency_hours} min={1}
                                onChange={e => updateTable(tableIdx, { check_frequency_hours: Number(e.target.value) })} />
                            </div>
                          </div>
                          <textarea value={table.description || ''} rows={2}
                            onChange={e => updateTable(tableIdx, { description: e.target.value })}
                            placeholder="Table description (optional)..." />

                          <div className="entries-section">
                            <strong>Entries ({visibleEntries.length})</strong>
                            {visibleEntries.length === 0 && <p className="empty-hint">No entries yet.</p>}
                            {(table.encounter_table_entries || []).map((entry, entryIdx) => {
                              if (entry._destroy) return null
                              return (
                                <div key={entry.id || `entry-${entryIdx}`} className="entry-card">
                                  <div className="entry-header">
                                    <input type="text" className="inline-name" value={entry.title}
                                      onChange={e => updateEntry(tableIdx, entryIdx, { title: e.target.value })}
                                      placeholder="Entry title" />
                                    <div className="entry-type-toggle">
                                      <button
                                        className={`type-btn ${entry.entry_type === 'fixed' ? 'active' : ''}`}
                                        onClick={() => updateEntry(tableIdx, entryIdx, { entry_type: 'fixed' })}>
                                        Fixed
                                      </button>
                                      <button
                                        className={`type-btn ${entry.entry_type === 'ai_prompt' ? 'active' : ''}`}
                                        onClick={() => updateEntry(tableIdx, entryIdx, { entry_type: 'ai_prompt' })}>
                                        ✦ AI
                                      </button>
                                    </div>
                                    <label className="weight-label">
                                      W:
                                      <input type="number" className="weight-input" value={entry.weight}
                                        min={1} onChange={e => updateEntry(tableIdx, entryIdx, { weight: Number(e.target.value) })} />
                                    </label>
                                    <button className="btn-remove-sm" onClick={() => removeEntry(tableIdx, entryIdx)}>✕</button>
                                  </div>
                                  <textarea value={entry.description} rows={2}
                                    onChange={e => updateEntry(tableIdx, entryIdx, { description: e.target.value })}
                                    placeholder={entry.entry_type === 'fixed'
                                      ? 'Full encounter description...'
                                      : 'AI prompt hint — the AI will expand this into a scene...'} />
                                </div>
                              )
                            })}
                            <button className="btn-add-sm" onClick={() => addEntry(tableIdx)}>+ Add Entry</button>
                          </div>
                        </div>
                      )}
                    </div>
                  )
                })}

                <button className="btn-add" onClick={() => setEncounterTables(prev => [...prev, emptyTable()])}>
                  + Add Encounter Table
                </button>
              </div>
            )}
          </div>
        )}

        <div className="editor-actions">
          <button className="btn-save" onClick={saveStory} disabled={saving || !canSave}>
            {saving ? 'Saving...' : isNew ? 'Create Story' : 'Save Changes'}
          </button>
        </div>
      </div>
    </div>
  )
}

export default AdminStoryEditor
