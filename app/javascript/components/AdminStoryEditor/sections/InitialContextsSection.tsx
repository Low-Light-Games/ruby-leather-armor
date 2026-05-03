import CollapsibleSection from '../components/CollapsibleSection'
import TagListEditor from '../components/TagListEditor'
import type {
  TraversalCtx, CombatCtx, SocialCtx, ExplorationCtx, RestCtx, InventoryCtx, SocialNpcPresent,
} from '../types'
import { emptySocialNpc } from '../types'

interface InitialContextsSectionProps {
  initialContextsOpen: boolean
  setInitialContextsOpen: (open: boolean) => void
  icSubOpen: Record<string, boolean>
  setIcSubOpen: React.Dispatch<React.SetStateAction<Record<string, boolean>>>
  icTraversal: TraversalCtx
  setIcTraversal: React.Dispatch<React.SetStateAction<TraversalCtx>>
  icCombat: CombatCtx
  setIcCombat: React.Dispatch<React.SetStateAction<CombatCtx>>
  icSocial: SocialCtx
  setIcSocial: React.Dispatch<React.SetStateAction<SocialCtx>>
  icExploration: ExplorationCtx
  setIcExploration: React.Dispatch<React.SetStateAction<ExplorationCtx>>
  icRest: RestCtx
  setIcRest: React.Dispatch<React.SetStateAction<RestCtx>>
  icInventory: InventoryCtx
  setIcInventory: React.Dispatch<React.SetStateAction<InventoryCtx>>
}

const SubHeader = ({
  label, title, sectionKey, icSubOpen, setIcSubOpen,
}: {
  label: string; title: string; sectionKey: string
  icSubOpen: Record<string, boolean>
  setIcSubOpen: React.Dispatch<React.SetStateAction<Record<string, boolean>>>
}) => (
  <div className="nested-card-header">
    <button className="expand-btn" onClick={() => setIcSubOpen(p => ({ ...p, [sectionKey]: !p[sectionKey] }))}>
      {icSubOpen[sectionKey] ? '▾' : '▸'}
    </button>
    <span className="inline-name" style={{ cursor: 'default', fontWeight: 600 }} title={title}>{label}</span>
  </div>
)

const InitialContextsSection = ({
  initialContextsOpen, setInitialContextsOpen,
  icSubOpen, setIcSubOpen,
  icTraversal, setIcTraversal,
  icCombat, setIcCombat,
  icSocial, setIcSocial,
  icExploration, setIcExploration,
  icRest, setIcRest,
  icInventory, setIcInventory,
}: InitialContextsSectionProps) => (
  <CollapsibleSection
    label="Initial Contexts"
    open={initialContextsOpen}
    onToggle={() => setInitialContextsOpen(!initialContextsOpen)}
    hint='Structured starting game state seeded into every new adventure.'
  >
    {/* -- Traversal -- */}
    <div className="nested-card">
      <SubHeader label="Traversal" sectionKey="traversal" icSubOpen={icSubOpen} setIcSubOpen={setIcSubOpen}
        title="Where the player physically is when the adventure begins. This is the most important context to fill — it prevents the sanity checker from blocking basic movement." />
      {icSubOpen.traversal && (
        <div className="nested-card-body">
          <div className="form-field compact">
            <label title="The specific place the player starts in. This becomes traversal_context.current_location — every AI step reads it to know where the player is.">Starting location</label>
            <input type="text" value={icTraversal.current_location}
              onChange={e => setIcTraversal(p => ({ ...p, current_location: e.target.value }))}
              placeholder="Be specific: 'upstairs bedroom at the Village Inn', not just 'Village Inn'" />
          </div>
          <div className="form-field compact">
            <label title="Only set this if the story begins mid-journey. Leave empty if the player starts stationary.">Destination (if mid-travel)</label>
            <input type="text" value={icTraversal.destination}
              onChange={e => setIcTraversal(p => ({ ...p, destination: e.target.value }))}
              placeholder="Leave empty unless the player starts already traveling somewhere" />
          </div>
          <div className="form-field compact">
            <label title="The type of ground/environment. Used by the narrator for descriptions and by mechanics for terrain-dependent checks.">Terrain type</label>
            <input type="text" value={icTraversal.terrain}
              onChange={e => setIcTraversal(p => ({ ...p, terrain: e.target.value }))}
              placeholder="indoor wooden floor, outdoor dirt road, forest undergrowth, cave stone, ..." />
          </div>
          <div className="form-field compact">
            <label title="Current weather at the start. Affects narrator prose and some mechanics (e.g. perception penalties in rain).">Weather</label>
            <input type="text" value={icTraversal.weather}
              onChange={e => setIcTraversal(p => ({ ...p, weather: e.target.value }))}
              placeholder="clear skies, light rain, heavy fog, snowfall, ..." />
          </div>
          <div className="form-field compact">
            <label title="General time description. The exact hour comes from the time_context system, but this helps the narrator set the mood.">Time of day</label>
            <input type="text" value={icTraversal.time_of_day}
              onChange={e => setIcTraversal(p => ({ ...p, time_of_day: e.target.value }))}
              placeholder="early morning, midday, late afternoon, dusk, midnight, ..." />
          </div>
          <div className="form-field compact">
            <label title="Ways out of the starting location. CRITICAL: if left empty, the sanity checker may block the player from leaving. List every obvious exit — doors, windows, paths, staircases.">Known exits</label>
            <TagListEditor items={icTraversal.exits}
              onChange={exits => setIcTraversal(p => ({ ...p, exits }))}
              placeholder="door to hallway, window overlooking the street, staircase down, ..."
              addLabel="+ Add exit" />
          </div>
          <div className="form-field compact">
            <label title="NPCs visibly present at the starting location. Must match NPC names from the NPCs section.">Nearby NPCs</label>
            <TagListEditor items={icTraversal.nearby_npcs}
              onChange={nearby_npcs => setIcTraversal(p => ({ ...p, nearby_npcs }))}
              placeholder="Must match an NPC name from the NPCs section"
              addLabel="+ Add NPC" />
          </div>
          <div className="form-field compact">
            <label title="Notable objects or features the player can see or interact with at the starting location.">Points of interest</label>
            <TagListEditor items={icTraversal.points_of_interest}
              onChange={points_of_interest => setIcTraversal(p => ({ ...p, points_of_interest }))}
              placeholder="a notice board, a locked chest, a campfire, an old well, ..."
              addLabel="+ Add point" />
          </div>
        </div>
      )}
    </div>

    {/* -- Combat -- */}
    <div className="nested-card">
      <SubHeader label="Combat" sectionKey="combat" icSubOpen={icSubOpen} setIcSubOpen={setIcSubOpen}
        title="Only fill this if the story begins mid-combat (e.g. an ambush as the opening scene). Most stories leave this empty." />
      {icSubOpen.combat && (
        <div className="nested-card-body">
          <label className="checkbox-group" title="When checked, the pipeline treats the first player input as a combat action.">
            <input type="checkbox" checked={icCombat.active}
              onChange={e => setIcCombat(p => ({ ...p, active: e.target.checked }))} />
            Combat active at start
          </label>
          {icCombat.active && (
            <p className="section-hint">The player will be in initiative order from turn one. Encounter participants come from the story's encounter tables — make sure those are set up.</p>
          )}
          <div className="form-field compact">
            <label title="Which round of combat the fight starts in. Usually 1 unless you're dropping the player into an already ongoing battle.">Starting round</label>
            <input type="number" value={icCombat.round ?? ''} min={1}
              onChange={e => setIcCombat(p => ({ ...p, round: e.target.value ? Number(e.target.value) : null }))}
              placeholder="1" />
          </div>
          <div className="form-field compact">
            <label title="Describes the battlefield. The narrator uses this for combat descriptions. Pathfinder terrain keywords (difficult terrain, cover, elevation) are most useful.">Terrain / battlefield notes</label>
            <input type="text" value={icCombat.terrain_notes}
              onChange={e => setIcCombat(p => ({ ...p, terrain_notes: e.target.value }))}
              placeholder="narrow corridor with difficult terrain, open field with scattered boulders for cover, ..." />
          </div>
        </div>
      )}
    </div>

    {/* -- Social -- */}
    <div className="nested-card">
      <SubHeader label="Social" sectionKey="social" icSubOpen={icSubOpen} setIcSubOpen={setIcSubOpen}
        title="Fill this if the adventure opens with an ongoing conversation or social encounter. Otherwise leave empty — it will populate naturally during play." />
      {icSubOpen.social && (
        <div className="nested-card-body">
          <div className="form-field compact">
            <label title="Brief summary of what's happening socially when the adventure starts. The chronicler uses this to track conversation progression.">Scene description</label>
            <input type="text" value={icSocial.scene}
              onChange={e => setIcSocial(p => ({ ...p, scene: e.target.value }))}
              placeholder="The innkeeper is chatting with a hooded stranger at the bar; a merchant argues with a guard at the door" />
          </div>
          <div className="form-field compact">
            <label title="Where in the conversation things stand. Helps the AI know whether to have NPCs introduce themselves or continue an ongoing exchange.">Conversation state</label>
            <input type="text" value={icSocial.conversation_state}
              onChange={e => setIcSocial(p => ({ ...p, conversation_state: e.target.value }))}
              placeholder="not yet started, introductions, mid-negotiation, heated argument, ..." />
          </div>
          <div className="form-field compact">
            <label title="What's at risk in this social encounter. Guides the AI in setting DCs and consequences for Diplomacy/Intimidate/Bluff checks.">Stakes</label>
            <input type="text" value={icSocial.stakes}
              onChange={e => setIcSocial(p => ({ ...p, stakes: e.target.value }))}
              placeholder="Gaining the elder's trust, buying supplies at a fair price, getting directions to the ruins, ..." />
          </div>
          <div className="form-field compact">
            <label title="NPCs the player can interact with right now. Names should match the NPC records you defined above. Attitude influences initial Diplomacy DCs.">NPCs in the social scene</label>
            {icSocial.npcs_present.map((npc, i) => (
              <div key={i} className="connection-row">
                <input type="text" value={npc.name} placeholder="NPC name (match NPCs section)"
                  onChange={e => setIcSocial(p => ({ ...p, npcs_present: p.npcs_present.map((n, j) => j === i ? { ...n, name: e.target.value } : n) }))} />
                <input type="text" value={npc.role} placeholder="Role: innkeeper, guard, merchant, ..."
                  onChange={e => setIcSocial(p => ({ ...p, npcs_present: p.npcs_present.map((n, j) => j === i ? { ...n, role: e.target.value } : n) }))} />
                <select value={npc.attitude} title="Starting attitude toward the player (Pathfinder Diplomacy scale)"
                  onChange={e => setIcSocial(p => ({ ...p, npcs_present: p.npcs_present.map((n, j) => j === i ? { ...n, attitude: e.target.value as SocialNpcPresent['attitude'] } : n) }))}>
                  <option value="friendly">friendly</option>
                  <option value="indifferent">indifferent</option>
                  <option value="unfriendly">unfriendly</option>
                </select>
                <input type="text" value={npc.notes} placeholder="Extra detail: nervous, hiding something, will offer a quest, ..."
                  onChange={e => setIcSocial(p => ({ ...p, npcs_present: p.npcs_present.map((n, j) => j === i ? { ...n, notes: e.target.value } : n) }))} />
                <button className="btn-remove-sm" onClick={() => setIcSocial(p => ({ ...p, npcs_present: p.npcs_present.filter((_, j) => j !== i) }))}>&#x2715;</button>
              </div>
            ))}
            <button className="btn-add-sm" onClick={() => setIcSocial(p => ({ ...p, npcs_present: [...p.npcs_present, emptySocialNpc()] }))}>+ Add NPC</button>
          </div>
        </div>
      )}
    </div>

    {/* -- Exploration -- */}
    <div className="nested-card">
      <SubHeader label="Exploration" sectionKey="exploration" icSubOpen={icSubOpen} setIcSubOpen={setIcSubOpen}
        title="Pre-seeded exploration state. Usually empty for new stories. Fill if the player should already know about certain items, secrets, or searched areas before play begins." />
      {icSubOpen.exploration && (
        <div className="nested-card-body">
          <div className="form-field compact">
            <label title="A detection spell or ability already active when the adventure starts (e.g. Detect Magic). Leave empty if none.">Active detection</label>
            <input type="text" value={icExploration.active_detection}
              onChange={e => setIcExploration(p => ({ ...p, active_detection: e.target.value }))}
              placeholder="Detect Magic, Detect Evil, ... (usually empty)" />
          </div>
          <div className="form-field compact">
            <label title="Areas the player has already searched before the adventure begins. Items here won't trigger new Perception checks.">Already searched areas</label>
            <TagListEditor items={icExploration.searched_areas}
              onChange={searched_areas => setIcExploration(p => ({ ...p, searched_areas }))}
              placeholder="the bedroom nightstand, the front porch, ..."
              addLabel="+ Add area" />
          </div>
          <div className="form-field compact">
            <label title="Items the player already found or has knowledge of. These show up as known in the exploration tracker.">Already discovered items</label>
            <TagListEditor items={icExploration.discovered_items}
              onChange={discovered_items => setIcExploration(p => ({ ...p, discovered_items }))}
              placeholder="a tattered journal, a rusted key, ..."
              addLabel="+ Add item" />
          </div>
          <div className="form-field compact">
            <label title="Hidden information the player already knows going in. Rare — only use for stories that pick up after a prior event.">Already discovered secrets</label>
            <TagListEditor items={icExploration.discovered_secrets}
              onChange={discovered_secrets => setIcExploration(p => ({ ...p, discovered_secrets }))}
              placeholder="the innkeeper works for the bandits, the well leads to underground tunnels, ..."
              addLabel="+ Add secret" />
          </div>
          <div className="form-field compact">
            <label title="Open threads the player is aware of but hasn't resolved yet. These appear in the exploration tracker as active leads.">Pending investigations</label>
            <TagListEditor items={icExploration.pending_investigations}
              onChange={pending_investigations => setIcExploration(p => ({ ...p, pending_investigations }))}
              placeholder="strange noises from the cellar, the missing merchant's last known route, ..."
              addLabel="+ Add investigation" />
          </div>
        </div>
      )}
    </div>

    {/* -- Rest -- */}
    <div className="nested-card">
      <SubHeader label="Rest" sectionKey="rest" icSubOpen={icSubOpen} setIcSubOpen={setIcSubOpen}
        title="Only fill this if the story opens while the player is mid-rest (e.g. woken by an ambush during a long rest). Almost always left empty." />
      {icSubOpen.rest && (
        <div className="nested-card-body">
          <label className="checkbox-group" title="Check if the player is currently in a long rest when the adventure begins. This blocks spell recovery and affects how interruptions are handled.">
            <input type="checkbox" checked={icRest.resting}
              onChange={e => setIcRest(p => ({ ...p, resting: e.target.checked }))} />
            Currently resting
          </label>
          <label className="checkbox-group" title="Check if the rest has already finished and the player simply hasn't acted yet. Enables spell/HP recovery processing on the first turn.">
            <input type="checkbox" checked={icRest.rest_complete}
              onChange={e => setIcRest(p => ({ ...p, rest_complete: e.target.checked }))} />
            Rest complete
          </label>
          <div className="form-field compact">
            <label title="How many hours of the rest have elapsed so far. E.g. if woken 4 hours into an 8-hour rest, set to 4.">Hours completed</label>
            <input type="number" value={icRest.hours_completed ?? ''} min={0}
              onChange={e => setIcRest(p => ({ ...p, hours_completed: e.target.value ? Number(e.target.value) : null }))}
              placeholder="0" />
          </div>
          <div className="form-field compact">
            <label title="Total hours needed for a full rest. Standard Pathfinder long rest is 8 hours.">Total hours needed</label>
            <input type="number" value={icRest.total_hours_needed ?? ''} min={0}
              onChange={e => setIcRest(p => ({ ...p, total_hours_needed: e.target.value ? Number(e.target.value) : null }))}
              placeholder="8" />
          </div>
          <div className="form-field compact">
            <label title="HP already recovered before the adventure starts. Usually 0 unless the story picks up after a partial rest.">HP recovered so far</label>
            <input type="number" value={icRest.hp_recovered ?? ''} min={0}
              onChange={e => setIcRest(p => ({ ...p, hp_recovered: e.target.value ? Number(e.target.value) : null }))}
              placeholder="0" />
          </div>
        </div>
      )}
    </div>

    {/* -- Inventory -- */}
    <div className="nested-card">
      <SubHeader label="Inventory" sectionKey="inventory" icSubOpen={icSubOpen} setIcSubOpen={setIcSubOpen}
        title="Tracks notable inventory changes between turns. Almost always empty at story start — the character sheet holds the full inventory. Only fill if the story gives the player a special item right away." />
      {icSubOpen.inventory && (
        <div className="nested-card-body">
          <div className="form-field compact">
            <label title="Items the player has just received or found. These are highlighted in the inventory tracker as new acquisitions.">Recently acquired items</label>
            <TagListEditor items={icInventory.recently_acquired}
              onChange={recently_acquired => setIcInventory(p => ({ ...p, recently_acquired }))}
              placeholder="a sealed letter from the mayor, a healing potion, ..."
              addLabel="+ Add item" />
          </div>
          <div className="form-field compact">
            <label title="Limited-use items the player has on hand (potions, scrolls, wands with charges). The pipeline uses this to validate consumable usage.">Notable consumables on hand</label>
            <TagListEditor items={icInventory.notable_consumables_remaining}
              onChange={notable_consumables_remaining => setIcInventory(p => ({ ...p, notable_consumables_remaining }))}
              placeholder="Potion of Cure Light Wounds, Scroll of Identify, 3 torches, ..."
              addLabel="+ Add consumable" />
          </div>
          <div className="form-field compact">
            <label title="Equipment the player has equipped differently from their character sheet defaults. E.g. if the story starts with armor removed.">Equipment overrides</label>
            <TagListEditor items={icInventory.equipped_changes}
              onChange={equipped_changes => setIcInventory(p => ({ ...p, equipped_changes }))}
              placeholder="armor removed (sleeping), wearing a disguise, borrowed longsword, ..."
              addLabel="+ Add change" />
          </div>
        </div>
      )}
    </div>
  </CollapsibleSection>
)

export default InitialContextsSection
