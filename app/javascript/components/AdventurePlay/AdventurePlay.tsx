import { useState, useEffect, useMemo, useCallback } from 'react'
import { useAuth } from '../../contexts/AuthContext'
import Navbar from '../Navbar'
import Login from '../Login'
import AdventureChat from '../AdventureChat'
import RollResultModal, { RollResultDisplay } from '../RollResultModal'
import { Adventure, AttributeType, DerivedStats } from '../../types'
import { rollD20 } from '../../rules/dice'
import { formatCurrency } from '../../rules/pathfinder_items'
import type { Currency } from '../../rules/pathfinder_items_types'
import { getFeatById, featDisplayName } from '../../rules/pathfinder_feats'
import { getSpellById, getCastingStyle, getSpellsForClass, getAllSpells, hasSlotForSpell } from '../../rules/pathfinder_spells'
import type { SpellDefinition } from '../../rules/pathfinder_spells_types'
import './AdventurePlay.scss'

interface AdventurePlayProps {
  adventureId: number
}

const ATTRIBUTE_LABELS: AttributeType[] = ['strength', 'dexterity', 'constitution', 'intelligence', 'wisdom', 'charisma']

const ABILITY_ABBR: Record<string, string> = {
  strength: 'STR',
  dexterity: 'DEX',
  constitution: 'CON',
  intelligence: 'INT',
  wisdom: 'WIS',
  charisma: 'CHA',
}

function formatMod(mod: number): string {
  return mod >= 0 ? `+${mod}` : `${mod}`
}

export const AdventurePlay = ({ adventureId }: AdventurePlayProps) => {
  const { user, loading: authLoading } = useAuth()

  const [adventure, setAdventure] = useState<Adventure | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [showAttributes, setShowAttributes] = useState(true)
  const [showSkills, setShowSkills] = useState(false)
  const [showFeats, setShowFeats] = useState(false)
  const [showSpells, setShowSpells] = useState(false)
  const [rollDisplay, setRollDisplay] = useState<RollResultDisplay | null>(null)
  const [spellbookSearch, setSpellbookSearch] = useState('')
  const [spellbookSaving, setSpellbookSaving] = useState(false)

  const loadAdventure = useCallback(() => {
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

  useEffect(() => {
    loadAdventure()
  }, [loadAdventure])

  // Called when the AI advances the story stage
  const handleStageAdvance = useCallback(() => {
    loadAdventure()
  }, [loadAdventure])

  // Read server-computed derived stats from the adventure sheet.
  // The backend CharacterStats::Calculator is the single source of truth.
  const ds: DerivedStats | null = adventure?.adventure_sheet?.derived_stats ?? null

  // ---- Roll handlers ----

  const doRoll = useCallback((label: string, modifier: number, modifierLabel?: string) => {
    const result = rollD20(modifier)
    setRollDisplay({ label, result, modifierLabel })
  }, [])

  const rollMeleeAttack = useCallback(() => {
    if (!ds) return
    doRoll('Melee Attack', ds.melee_attack, `BAB ${formatMod(ds.bab)} + STR ${formatMod(ds.mods.strength)}`)
  }, [ds, doRoll])

  const rollRangedAttack = useCallback(() => {
    if (!ds) return
    doRoll('Ranged Attack', ds.ranged_attack, `BAB ${formatMod(ds.bab)} + DEX ${formatMod(ds.mods.dexterity)}`)
  }, [ds, doRoll])

  const rollFort = useCallback(() => {
    if (!ds) return
    doRoll('Fortitude Save', ds.fort, `Fort ${formatMod(ds.fort)}`)
  }, [ds, doRoll])

  const rollRef = useCallback(() => {
    if (!ds) return
    doRoll('Reflex Save', ds.ref, `Ref ${formatMod(ds.ref)}`)
  }, [ds, doRoll])

  const rollWill = useCallback(() => {
    if (!ds) return
    doRoll('Will Save', ds.will, `Will ${formatMod(ds.will)}`)
  }, [ds, doRoll])

  const rollInitiative = useCallback(() => {
    if (!ds) return
    doRoll('Initiative', ds.initiative, `Init ${formatMod(ds.initiative)}`)
  }, [ds, doRoll])

  const rollAbility = useCallback((attr: AttributeType) => {
    if (!ds) return
    const mod = ds.mods[attr]
    doRoll(`${ABILITY_ABBR[attr]} Check`, mod, `${ABILITY_ABBR[attr]} ${formatMod(mod)}`)
  }, [ds, doRoll])

  const rollSkill = useCallback((skillName: string, total: number) => {
    doRoll(`${skillName} Check`, total, `Skill ${formatMod(total)}`)
  }, [doRoll])

  // ─── Spellbook management (hooks must be above early returns) ─

  const spellbookSearchResults = useMemo(() => {
    if (!adventure || !ds) return []
    const sheet = adventure.adventure_sheet
    const castStyle = getCastingStyle(sheet.character_class)
    if (castStyle !== 'spellbook' || !spellbookSearch.trim()) return []
    const currentSpellIds: string[] = sheet.details?.spellbook || sheet.details?.spells || []
    const term = spellbookSearch.toLowerCase().trim()
    const classSpells = sheet.character_class
      ? getSpellsForClass(sheet.character_class, 9)
      : getAllSpells()
    return classSpells
      .filter(s => !currentSpellIds.includes(s.id))
      .filter(s => s.name.toLowerCase().includes(term) || s.school.includes(term))
      .map(spell => ({
        spell,
        hasSlot: hasSlotForSpell(
          sheet.character_class, sheet.level,
          ds.final_scores.intelligence, spell, currentSpellIds,
        ),
      }))
      .slice(0, 8)
  }, [adventure, ds, spellbookSearch])

  const addSpellToSpellbook = useCallback(async (spell: SpellDefinition) => {
    if (!adventure) return
    const sheet = adventure.adventure_sheet
    const currentSpellIds: string[] = sheet.details?.spellbook || sheet.details?.spells || []
    setSpellbookSaving(true)
    try {
      const newSpellbook = [...currentSpellIds, spell.id]
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || ''
      const res = await fetch(`/adventures/${adventure.id}/adventure_sheet`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
        body: JSON.stringify({ spellbook: newSpellbook }),
      })
      if (res.ok) {
        const updatedSheet = await res.json()
        setAdventure(prev => prev ? { ...prev, adventure_sheet: updatedSheet } : prev)
      }
    } catch (e) {
      console.error('Failed to update spellbook:', e)
    } finally {
      setSpellbookSaving(false)
      setSpellbookSearch('')
    }
  }, [adventure])

  // ---- Render ----

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

  if (error || !adventure || !ds) {
    return (
      <div className="app">
        <Navbar />
        <p className="feedback-error">{error || 'Adventure not found'}</p>
      </div>
    )
  }

  const { adventure_sheet: sheet, story, story_state } = adventure
  const feats = sheet.details?.feats || []
  const castStyle = getCastingStyle(sheet.character_class)

  // Read spells from the correct detail field based on casting style
  const spellIds: string[] = (() => {
    if (castStyle === 'spontaneous') return sheet.details?.knownSpells || sheet.details?.spells || []
    if (castStyle === 'spellbook') return sheet.details?.spellbook || sheet.details?.spells || []
    return sheet.details?.spells || []
  })()

  const spellSectionLabel = castStyle === 'spellbook' ? 'Spellbook'
    : castStyle === 'spontaneous' ? 'Known Spells'
    : 'Spells'

  return (
    <div className="app">
      <Navbar />
      <div className="adventure-play">
        {/* LEFT COLUMN — Character */}
        <div className="adventure-column character-column">
          <h2>{sheet.name}</h2>
          {(sheet.race || sheet.character_class) && (
            <p className="char-subtitle">
              {[sheet.race, sheet.character_class].filter(Boolean).join(' ')}
              {sheet.level > 1 && ` (Lv ${sheet.level})`}
            </p>
          )}

          {/* Always-visible combat stats */}
          <div className="combat-stats">
            <div className="combat-stat">
              <span className="stat-label">AC</span>
              <span className="stat-value">{ds.ac}</span>
            </div>
            <div className="combat-stat">
              <span className="stat-label">Touch AC</span>
              <span className="stat-value">{ds.touch_ac}</span>
            </div>
            <div className="combat-stat">
              <span className="stat-label">Flat-Foot</span>
              <span className="stat-value">{ds.flat_footed_ac}</span>
            </div>
            <div className="combat-stat">
              <span className="stat-label">HP</span>
              <span className="stat-value">{sheet.hp} / {ds.max_hp}</span>
            </div>
            <div className="combat-stat">
              <span className="stat-label">BAB</span>
              <span className="stat-value">{formatMod(ds.bab)}</span>
            </div>
            <div className="combat-stat">
              <span className="stat-label">CMB</span>
              <span className="stat-value">{formatMod(ds.cmb)}</span>
            </div>
            <div className="combat-stat">
              <span className="stat-label">CMD</span>
              <span className="stat-value">{ds.cmd}</span>
            </div>
            <div className="combat-stat">
              <span className="stat-label">Speed</span>
              <span className="stat-value">{ds.speed} ft</span>
            </div>
          </div>

          <div className="saves-row">
            <button className="save-item rollable" onClick={rollFort} title="Roll Fortitude Save">
              <span className="save-label">Fort</span>
              <span className="save-value">{formatMod(ds.fort)}</span>
              <span className="roll-dice-hint">🎲</span>
            </button>
            <button className="save-item rollable" onClick={rollRef} title="Roll Reflex Save">
              <span className="save-label">Ref</span>
              <span className="save-value">{formatMod(ds.ref)}</span>
              <span className="roll-dice-hint">🎲</span>
            </button>
            <button className="save-item rollable" onClick={rollWill} title="Roll Will Save">
              <span className="save-label">Will</span>
              <span className="save-value">{formatMod(ds.will)}</span>
              <span className="roll-dice-hint">🎲</span>
            </button>
          </div>

          <div className="adventure-gold">
            <span className="stat-label">Currency</span>
            <span className="stat-value gold">{formatCurrency(sheet.currency as Currency)}</span>
          </div>

          {/* Stacked collapsible sections */}
          <div className="collapsible-sections">
            {/* Attributes */}
            <div className="collapsible-section">
              <button
                className={`collapsible-header ${showAttributes ? 'open' : ''}`}
                onClick={() => setShowAttributes(prev => !prev)}
              >
                <span className="collapse-icon">{showAttributes ? '▼' : '▶'}</span>
                Attributes
              </button>
              {showAttributes && (
                <div className="collapsible-body">
                  <div className="attributes-list">
                    {ATTRIBUTE_LABELS.map(attr => {
                      const base = sheet[attr]
                      const final = ds.final_scores[attr] ?? base
                      const racial = final - base
                      const mod = ds.mods[attr] ?? 0
                      return (
                        <div key={attr} className="attribute-item">
                          <span className="attr-label">{ABILITY_ABBR[attr]}</span>
                          <span className="attr-score">
                            {base}
                            {racial !== 0 && (
                              <span className={`racial ${racial > 0 ? 'pos' : 'neg'}`}>
                                {racial > 0 ? '+' : ''}{racial}
                              </span>
                            )}
                            {' = '}
                            <strong>{final}</strong>
                          </span>
                          <span className="attr-mod">{formatMod(mod)}</span>
                          <button
                            className="roll-dice-btn"
                            onClick={() => rollAbility(attr)}
                            title={`Roll ${ABILITY_ABBR[attr]} Check`}
                            aria-label={`Roll ${ABILITY_ABBR[attr]} Check`}
                          >
                            🎲
                          </button>
                        </div>
                      )
                    })}
                  </div>
                </div>
              )}
            </div>

            {/* Skills */}
            <div className="collapsible-section">
              <button
                className={`collapsible-header ${showSkills ? 'open' : ''}`}
                onClick={() => setShowSkills(prev => !prev)}
              >
                <span className="collapse-icon">{showSkills ? '▼' : '▶'}</span>
                Skills
              </button>
              {showSkills && (
                <div className="collapsible-body">
                  <div className="skills-list-adventure">
                    {ds.skills.map(skill => (
                      <div
                        key={skill.name}
                        className={`skill-row ${skill.trained_only ? 'trained-only' : ''}`}
                      >
                        <span className="skill-name">
                          {skill.name}
                          {skill.trained_only && <span className="badge-t">T</span>}
                        </span>
                        <span className={`skill-mod ${skill.total >= 0 ? 'positive' : 'negative'}`}>
                          {formatMod(skill.total)}
                        </span>
                        <button
                          className="roll-dice-btn"
                          onClick={() => rollSkill(skill.name, skill.total)}
                          title={`Roll ${skill.name} Check`}
                          aria-label={`Roll ${skill.name} Check`}
                        >
                          🎲
                        </button>
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </div>

            {/* Feats */}
            <div className="collapsible-section">
              <button
                className={`collapsible-header ${showFeats ? 'open' : ''}`}
                onClick={() => setShowFeats(prev => !prev)}
              >
                <span className="collapse-icon">{showFeats ? '▼' : '▶'}</span>
                Feats ({feats.length})
              </button>
              {showFeats && (
                <div className="collapsible-body">
                  <div className="feats-spells-list">
                    {feats.length === 0 ? (
                      <p className="empty-hint">No feats selected.</p>
                    ) : (
                      feats.map(entry => {
                        const feat = getFeatById(entry)
                        if (!feat) return null
                        const displayName = featDisplayName(entry)
                        return (
                          <div key={entry} className="fs-item" title={feat.summary}>
                            <span className="fs-name">{displayName}</span>
                            <span className={`fs-tag cat-${feat.category}`}>{feat.category}</span>
                          </div>
                        )
                      })
                    )}
                  </div>
                </div>
              )}
            </div>

            {/* Spells */}
            <div className="collapsible-section">
              <button
                className={`collapsible-header ${showSpells ? 'open' : ''}`}
                onClick={() => setShowSpells(prev => !prev)}
              >
                <span className="collapse-icon">{showSpells ? '▼' : '▶'}</span>
                {spellSectionLabel} ({spellIds.length})
              </button>
              {showSpells && (
                <div className="collapsible-body">
                  {/* Prepared full-list notice */}
                  {castStyle === 'prepared_list' && (
                    <p className="empty-hint" style={{ fontStyle: 'italic' }}>
                      Your class knows all spells. Daily preparation coming soon.
                    </p>
                  )}

                  <div className="feats-spells-list">
                    {spellIds.length === 0 ? (
                      <p className="empty-hint">
                        {castStyle === 'spellbook' ? 'Spellbook is empty.' :
                         castStyle === 'spontaneous' ? 'No known spells.' :
                         'No spells selected.'}
                      </p>
                    ) : (
                      spellIds.map(spellId => {
                        const spell = getSpellById(spellId)
                        if (!spell) return null
                        const lvl = sheet.character_class
                          ? spell.classLevels[sheet.character_class.toLowerCase()]
                          : Object.values(spell.classLevels)[0]
                        return (
                          <div key={spell.id} className="fs-item" title={spell.summary}>
                            <span className="spell-lvl-badge">{lvl ?? '?'}</span>
                            <span className="fs-name">{spell.name}</span>
                            <span className="fs-tag school-tag">{spell.school}</span>
                          </div>
                        )
                      })
                    )}
                  </div>

                  {/* Spellbook editing (wizard only during adventure) */}
                  {castStyle === 'spellbook' && (
                    <div className="spellbook-add-section">
                      <p className="spellbook-add-label">Add spell to spellbook:</p>
                      <input
                        type="text"
                        className="spellbook-search-input"
                        placeholder="Search spells to add…"
                        value={spellbookSearch}
                        onChange={e => setSpellbookSearch(e.target.value)}
                        disabled={spellbookSaving}
                      />
                      {spellbookSearchResults.length > 0 && (
                        <ul className="spellbook-dropdown">
                          {spellbookSearchResults.map(({ spell, hasSlot }) => {
                            const lvl = sheet.character_class
                              ? spell.classLevels[sheet.character_class.toLowerCase()]
                              : '?'
                            return (
                              <li
                                key={spell.id}
                                className={`spellbook-option ${!hasSlot ? 'slot-full' : ''}`}
                                onClick={() => hasSlot && addSpellToSpellbook(spell)}
                              >
                                <span className="spell-lvl-badge small">{lvl ?? '?'}</span>
                                <span className="option-name">{spell.name}</span>
                                <span className="fs-tag school-tag">{spell.school}</span>
                                {!hasSlot && <span className="slot-full-hint">slots full</span>}
                              </li>
                            )
                          })}
                        </ul>
                      )}
                    </div>
                  )}
                </div>
              )}
            </div>
          </div>

          {/* Roll buttons */}
          <div className="roll-buttons">
            <h3>Actions</h3>
            <button className="roll-btn attack" onClick={rollMeleeAttack}>⚔️ Melee Attack</button>
            <button className="roll-btn ranged" onClick={rollRangedAttack}>🏹 Ranged Attack</button>
            <button className="roll-btn initiative" onClick={rollInitiative}>⏱️ Roll Initiative</button>
          </div>
        </div>

        {/* MIDDLE COLUMN — Chat */}
        <div className="adventure-column middle-column">
          <AdventureChat
            adventureId={adventureId}
            onStageAdvance={handleStageAdvance}
          />
        </div>

        {/* RIGHT COLUMN — Story */}
        <div className="adventure-column story-column">
          <h2>{story.title}</h2>
          <p className="story-stage">{story_state.description}</p>
        </div>
      </div>

      {/* Roll Result Modal */}
      <RollResultModal roll={rollDisplay} onClose={() => setRollDisplay(null)} />
    </div>
  )
}

export default AdventurePlay
