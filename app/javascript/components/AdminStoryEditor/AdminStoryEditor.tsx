import Login from '../Login'
import FlashMessage from '../FlashMessage'
import { useStoryEditorState } from './useStoryEditorState'
import LocationsSection from './sections/LocationsSection'
import EncounterTablesSection from './sections/EncounterTablesSection'
import NpcsSection from './sections/NpcsSection'
import SeedFactsSection from './sections/SeedFactsSection'
import type { AdminStoryEditorProps } from './types'
import './AdminStoryEditor.scss'

export const AdminStoryEditor = ({ mode, storyId }: AdminStoryEditorProps) => {
  const state = useStoryEditorState(mode, storyId)
  const {
    user, authLoading, loading, saving, feedback, dismissFeedback,
    title, setTitle, preview, setPreview, premise, setPremise,
    openingMessage, setOpeningMessage,
    hiddenFromPlayers, setHiddenFromPlayers,
    seedFacts, setSeedFacts,
    currentStoryId,
    locations, setLocations,
    encounterTables, setEncounterTables,
    npcs, setNpcs,
    seedFactsOpen, setSeedFactsOpen,
    locationsOpen, setLocationsOpen,
    encounterTablesOpen, setEncounterTablesOpen,
    npcsOpen, setNpcsOpen,
    expandedLocIdx, setExpandedLocIdx,
    expandedTableIdx, setExpandedTableIdx,
    duplicateNames, hasDuplicateNames,
    saveStory,
  } = state

  if (authLoading) return <div className="admin-page">Loading...</div>
  if (!user) return <Login />
  if (!user.admin) {
    return (
      <div className="admin-page">
        <p className="feedback-error">Admin access required.</p>
      </div>
    )
  }

  if (loading) {
    return (
      <div className="admin-page">
        <p style={{ padding: '20px' }}>Loading story...</p>
      </div>
    )
  }

  const isNew = mode === 'create' && !currentStoryId
  const namedNpcsMissingSheet = npcs.filter(n =>
    !n._destroy && n.name.trim() !== '' && (!n.bestiary_entry || !n.bestiary_entry.id)
  )
  const hasNamedNpcMissingSheet = namedNpcsMissingSheet.length > 0
  const canSave = title.trim() && preview.trim() && premise.trim() && openingMessage.trim()
    && !hasDuplicateNames && !hasNamedNpcMissingSheet
  const isEditMode = !!currentStoryId
  const savedLocations = locations.filter(l => l.id && !l._destroy)
  const savedNpcs = npcs.filter(n => n.id && !n._destroy)

  return (
    <div className="admin-page">
      <div className="admin-story-editor">
        <div className="editor-top">
          <a href="/admin/stories" className="back-link">&larr; Back to Stories</a>
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
          <label htmlFor="story-title" title="The story's display name, shown in the adventure picker and admin list.">Title</label>
          <input type="text" id="story-title" value={title}
            onChange={e => setTitle(e.target.value)} placeholder="The Goblin Caves, Shadow over Millhaven, ..." />
        </div>

        <div className="form-field">
          <label htmlFor="story-preview" title="A short teaser the player sees before starting the adventure. No spoilers.">Preview (shown to players)</label>
          <textarea id="story-preview" value={preview}
            onChange={e => setPreview(e.target.value)} rows={3}
            placeholder="1-2 sentences the player reads before choosing this story. Set the tone without revealing the plot." />
        </div>

        <div className="form-field">
          <label htmlFor="story-premise" title="The full plot, secrets, and villain motivations. Spoiler-bearing — only the AI sees this. The fact extractor reads it and the opening message together to populate seed_facts.">Premise (full story, admin only)</label>
          <textarea id="story-premise" value={premise}
            onChange={e => setPremise(e.target.value)} rows={6}
            placeholder="The complete plot with all secrets and twists. Who is the villain? What's really going on? Include NPC motivations, hidden connections, and the intended resolution. The AI DM reads this to run the story — the player never sees it." />
        </div>

        <div className="form-field">
          <label htmlFor="story-opening-message" title="Player-facing prose rendered as the first AdventureMessage at adventure creation. The fact extractor treats this as the live present moment, overriding premise on direct conflicts.">Opening Message (first scene the player sees)</label>
          <textarea id="story-opening-message" value={openingMessage}
            onChange={e => setOpeningMessage(e.target.value)} rows={5}
            placeholder="The first prose the player reads when they start the adventure. E.g. 'You wake at dawn in the inn at the crossroads, the rain still falling. The innkeeper Helena meets your eye across the common room — she has been waiting for you.'" />
        </div>

        <div className="form-field">
          <label htmlFor="story-hidden-from-players">
            <input
              type="checkbox"
              id="story-hidden-from-players"
              checked={hiddenFromPlayers}
              onChange={e => setHiddenFromPlayers(e.target.checked)}
            />
            &nbsp;Hidden from players
          </label>
        </div>

        {isEditMode && (
          <SeedFactsSection
            seedFacts={seedFacts} setSeedFacts={setSeedFacts}
            open={seedFactsOpen} setOpen={setSeedFactsOpen}
          />
        )}

        {isEditMode && (
          <LocationsSection
            locations={locations} setLocations={setLocations}
            locationsOpen={locationsOpen} setLocationsOpen={setLocationsOpen}
            expandedLocIdx={expandedLocIdx} setExpandedLocIdx={setExpandedLocIdx}
            duplicateNames={duplicateNames}
          />
        )}

        {isEditMode && (
          <EncounterTablesSection
            encounterTables={encounterTables} setEncounterTables={setEncounterTables}
            encounterTablesOpen={encounterTablesOpen} setEncounterTablesOpen={setEncounterTablesOpen}
            expandedTableIdx={expandedTableIdx} setExpandedTableIdx={setExpandedTableIdx}
          />
        )}

        {isEditMode && (
          <NpcsSection
            npcs={npcs} setNpcs={setNpcs}
            npcsOpen={npcsOpen} setNpcsOpen={setNpcsOpen}
            savedLocations={savedLocations}
            storyId={currentStoryId}
          />
        )}

        {hasNamedNpcMissingSheet && (
          <div className="feedback-error" style={{ marginTop: 12 }}>
            Generate a bestiary stat block for every named NPC before saving:&nbsp;
            {namedNpcsMissingSheet.map(n => n.name).join(', ')}
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
