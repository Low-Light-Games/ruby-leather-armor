import Login from '../Login'
import FlashMessage from '../FlashMessage'
import { useStoryEditorState } from './useStoryEditorState'
import LocationsSection from './sections/LocationsSection'
import EncounterTablesSection from './sections/EncounterTablesSection'
import NpcsSection from './sections/NpcsSection'
import CluesSection from './sections/CluesSection'
import MilestonesSection from './sections/MilestonesSection'
import InitialContextsSection from './sections/InitialContextsSection'
import type { AdminStoryEditorProps } from './types'
import './AdminStoryEditor.scss'

export const AdminStoryEditor = ({ mode, storyId }: AdminStoryEditorProps) => {
  const state = useStoryEditorState(mode, storyId)
  const {
    user, authLoading, loading, saving, feedback, dismissFeedback,
    title, setTitle, preview, setPreview, premise, setPremise,
    initialSummary, setInitialSummary,
    currentStoryId,
    locations, setLocations,
    encounterTables, setEncounterTables,
    npcs, setNpcs, clues, setClues, milestones, setMilestones,
    icTraversal, setIcTraversal, icCombat, setIcCombat,
    icSocial, setIcSocial, icExploration, setIcExploration,
    icRest, setIcRest, icInventory, setIcInventory,
    locationsOpen, setLocationsOpen,
    encounterTablesOpen, setEncounterTablesOpen,
    npcsOpen, setNpcsOpen, cluesOpen, setCluesOpen,
    milestonesOpen, setMilestonesOpen,
    initialContextsOpen, setInitialContextsOpen,
    icSubOpen, setIcSubOpen,
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
  const canSave = title.trim() && preview.trim() && premise.trim() && !hasDuplicateNames
  const isEditMode = !!currentStoryId
  const savedLocations = locations.filter(l => l.id && !l._destroy)
  const savedNpcs = npcs.filter(n => n.id && !n._destroy)
  const savedClues = clues.filter(c => c.id && !c._destroy)

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
          <label htmlFor="story-premise" title="The full plot, secrets, and villain motivations. Only the AI sees this — never shown to the player.">Premise (full story, admin only)</label>
          <textarea id="story-premise" value={premise}
            onChange={e => setPremise(e.target.value)} rows={6}
            placeholder="The complete plot with all secrets and twists. Who is the villain? What's really going on? Include NPC motivations, hidden connections, and the intended resolution. The AI DM reads this to run the story — the player never sees it." />
        </div>

        <div className="form-field">
          <label htmlFor="story-initial-summary" title="Seeds the 'story so far' field that the narrator and other steps use for context. Should reflect the starting state, not the plot.">Initial Summary (story-so-far seed)</label>
          <textarea id="story-initial-summary" value={initialSummary}
            onChange={e => setInitialSummary(e.target.value)} rows={4}
            placeholder="A brief status line from the player's perspective. E.g. 'Just arrived at the village after hearing rumors of goblin trouble. No leads yet.' This seeds the macro narrative tracker." />
        </div>

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
          />
        )}

        {isEditMode && (
          <CluesSection
            clues={clues} setClues={setClues}
            cluesOpen={cluesOpen} setCluesOpen={setCluesOpen}
            savedLocations={savedLocations}
            savedNpcs={savedNpcs}
            savedClues={savedClues}
          />
        )}

        {isEditMode && (
          <MilestonesSection
            milestones={milestones} setMilestones={setMilestones}
            milestonesOpen={milestonesOpen} setMilestonesOpen={setMilestonesOpen}
            savedClues={savedClues}
          />
        )}

        {isEditMode && (
          <InitialContextsSection
            initialContextsOpen={initialContextsOpen} setInitialContextsOpen={setInitialContextsOpen}
            icSubOpen={icSubOpen} setIcSubOpen={setIcSubOpen}
            icTraversal={icTraversal} setIcTraversal={setIcTraversal}
            icCombat={icCombat} setIcCombat={setIcCombat}
            icSocial={icSocial} setIcSocial={setIcSocial}
            icExploration={icExploration} setIcExploration={setIcExploration}
            icRest={icRest} setIcRest={setIcRest}
            icInventory={icInventory} setIcInventory={setIcInventory}
          />
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
