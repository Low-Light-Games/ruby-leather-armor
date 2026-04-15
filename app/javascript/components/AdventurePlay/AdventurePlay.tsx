import { useState } from 'react';
import { useAuth } from '../../contexts/AuthContext';
import Navbar from '../Navbar';
import Login from '../Login';
import AdventureChat from '../AdventureChat';
import RollResultModal from '../RollResultModal';
import { CharacterSidebar } from './CharacterSidebar';
import { StorySidebar } from './StorySidebar';
import { useAdventure } from './hooks/useAdventure';
import { useRolls } from './hooks/useRolls';
import { useSpellbook } from './hooks/useSpellbook';
import { useInventory } from './hooks/useInventory';
import { useAdventureSkillRanks } from './hooks/useAdventureSkillRanks';
import './AdventurePlay.scss';

type MobileTab = 'character' | 'play' | 'story';

interface AdventurePlayProps {
  adventureId: number;
}

export const AdventurePlay = ({ adventureId }: AdventurePlayProps) => {
  const { user, loading: authLoading } = useAuth();

  const { adventure, ds, loading, error, reload, setAdventure } = useAdventure(adventureId, user);
  const advSheet = adventure?.adventure_sheet ?? null;
  const rolls = useRolls(ds, advSheet);
  const spellbook = useSpellbook(adventure, ds, setAdventure);
  const inventory = useInventory(adventure, setAdventure);
  const skillRanks = useAdventureSkillRanks(adventure, setAdventure);
  const [mobileTab, setMobileTab] = useState<MobileTab>('play');

  // ── Early returns (loading / auth / error) ─────────────────────

  if (authLoading) {
    return <div className="app">Loading...</div>;
  }

  if (!user) {
    return <Login />;
  }

  if (user.banned) {
    return (
      <div className="app">
        <Navbar />
        <div className="banned-notice">
          <h2>Adventure Suspended</h2>
          <p>Your account has been suspended from all adventures and AI features.</p>
          <p>
            If you believe this was in error, contact{' '}
            <a href="mailto:appeals@leatheramor.io">appeals@leatheramor.io</a> to appeal.
          </p>
        </div>
      </div>
    );
  }

  if (loading) {
    return (
      <div className="app">
        <Navbar />
        <p>Loading adventure...</p>
      </div>
    );
  }

  if (error || !adventure || !ds) {
    return (
      <div className="app">
        <Navbar />
        <p className="feedback-error">{error || 'Adventure not found'}</p>
      </div>
    );
  }

  const { adventure_sheet: sheet, story } = adventure;

  return (
    <div className="app">
      <Navbar />
      <div className="adventure-play" data-mobile-tab={mobileTab}>
        {/* Mobile tab navigation — hidden on desktop */}
        <nav className="mobile-tab-nav" aria-label="Panel navigation">
          <button
            className={`mobile-tab-btn${mobileTab === 'character' ? ' active' : ''}`}
            onClick={() => setMobileTab('character')}
          >
            Character
          </button>
          <button
            className={`mobile-tab-btn${mobileTab === 'play' ? ' active' : ''}`}
            onClick={() => setMobileTab('play')}
          >
            Play
          </button>
          <button
            className={`mobile-tab-btn${mobileTab === 'story' ? ' active' : ''}`}
            onClick={() => setMobileTab('story')}
          >
            Story
          </button>
        </nav>

        {/* LEFT COLUMN — Character */}
        <CharacterSidebar
          sheet={sheet}
          ds={ds}
          rollFort={rolls.rollFort}
          rollRef={rolls.rollRef}
          rollWill={rolls.rollWill}
          rollMeleeAttack={rolls.rollMeleeAttack}
          rollRangedAttack={rolls.rollRangedAttack}
          rollInitiative={rolls.rollInitiative}
          rollAbility={rolls.rollAbility}
          rollSkill={rolls.rollSkill}
          rollWeaponDamage={rolls.rollWeaponDamage}
          rollSpellDamage={rolls.rollSpellDamage}
          rollUnarmedDamage={rolls.rollUnarmedDamage}
          rollConcentration={rolls.rollConcentration}
          concentrationMod={rolls.concentrationMod}
          spellbookSearch={spellbook.spellbookSearch}
          setSpellbookSearch={spellbook.setSpellbookSearch}
          spellbookSaving={spellbook.spellbookSaving}
          spellbookSearchResults={spellbook.spellbookSearchResults}
          addSpellToSpellbook={spellbook.addSpellToSpellbook}
          toggleEquip={inventory.toggleEquip}
          equipSaving={inventory.equipSaving}
          equipError={inventory.equipError}
          patchSkillRanks={skillRanks.patchSkillRanks}
          rankSaving={skillRanks.rankSaving}
          rankErrors={skillRanks.rankErrors}
          dismissRankErrors={skillRanks.dismissRankErrors}
        />

        {/* MIDDLE COLUMN — Chat */}
        <div className="adventure-column middle-column">
          {user.onboarding_state === 'in_progress' && (
            <div className="first-time-hint">
              <p>
                <strong>Your first adventure.</strong> Type what your character does and the DM will respond.
                Directed play is on — each turn ends with concrete choices to keep things moving.
              </p>
            </div>
          )}
          <AdventureChat
            adventureId={adventureId}
            derivedStats={ds}
            adventureSheet={advSheet}
            adventureEnded={adventure.ended}
            endReason={adventure.end_reason}
            onAdventureComplete={reload}
            onDmResponse={reload}
            onSheetUpdate={reload}
          />
        </div>

        {/* RIGHT COLUMN — Story */}
        <StorySidebar
          story={story}
          adventureId={adventureId}
          battlefield={adventure.battlefield ?? null}
          traversalContext={adventure.traversal_context}
          combatContext={adventure.combat_context}
          socialContext={adventure.social_context}
          explorationContext={adventure.exploration_context}
          restContext={adventure.rest_context}
          inventoryContext={adventure.inventory_context}
          timeContext={adventure.time_context}
          storySummary={adventure.story_summary}
          sceneSummary={adventure.scene_summary}
          currentCategory={adventure.current_category}
          onContextUpdate={(field, value) =>
            setAdventure(prev => prev ? { ...prev, [`${field}_context`]: value } : prev)
          }
        />
      </div>

      {/* Roll Result Modal */}
      <RollResultModal
        roll={rolls.rollDisplay}
        damageRoll={rolls.damageDisplay}
        onClose={() => { rolls.clearRoll(); rolls.clearDamage(); }}
      />
    </div>
  );
};

export default AdventurePlay;
