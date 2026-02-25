import { useState, useEffect, useMemo, useCallback } from 'react'
import { useAuth } from '../../contexts/AuthContext'
import Navbar from '../Navbar'
import Login from '../Login'
import AdventureChat from '../AdventureChat'
import RollResultModal, { RollResultDisplay } from '../RollResultModal'
import { Adventure, AttributeType } from '../../types'
import { PATHFINDER_SKILLS, abilityModifier } from '../../rules/pathfinder_skills'
import { getRaceById, computeRacialModifiers } from '../../rules/pathfinder_races'
import { getClassById } from '../../rules/pathfinder_classes'
import { rollD20 } from '../../rules/dice'
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

/**
 * Level-1 base save: Good = +2, Poor = +0
 */
function baseSave(good: boolean): number {
  return good ? 2 : 0
}

/**
 * Level-1 BAB: Full = +1, 3/4 = +0, 1/2 = +0
 */
function baseBAB(bab: string): number {
  return bab === 'full' ? 1 : 0
}

export const AdventurePlay = ({ adventureId }: AdventurePlayProps) => {
  const { user, loading: authLoading } = useAuth()

  const [adventure, setAdventure] = useState<Adventure | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [showSection, setShowSection] = useState<'attributes' | 'skills'>('attributes')
  const [rollDisplay, setRollDisplay] = useState<RollResultDisplay | null>(null)

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

  // Compute derived stats from the snapshot
  const derivedStats = useMemo(() => {
    if (!adventure) return null

    const snap = adventure.character_snapshot
    const race = snap.race ? getRaceById(snap.race) : undefined
    const classDef = snap.character_class ? getClassById(snap.character_class) : undefined

    // Compute racial modifiers
    const racialMods = computeRacialModifiers(
      race,
      (snap.racial_bonus_attribute as AttributeType) || null,
    )

    // Final ability scores
    const finalScores: Record<AttributeType, number> = {} as any
    for (const attr of ATTRIBUTE_LABELS) {
      finalScores[attr] = snap[attr] + (racialMods[attr] || 0)
    }

    // Ability modifiers
    const mods: Record<AttributeType, number> = {} as any
    for (const attr of ATTRIBUTE_LABELS) {
      mods[attr] = abilityModifier(finalScores[attr])
    }

    // Saving throws (level 1)
    const fortGood = classDef ? classDef.goodSaves.includes('fort') : false
    const refGood = classDef ? classDef.goodSaves.includes('ref') : false
    const willGood = classDef ? classDef.goodSaves.includes('will') : false

    const fortitude = baseSave(fortGood) + mods.constitution
    const reflex = baseSave(refGood) + mods.dexterity
    const will = baseSave(willGood) + mods.wisdom

    // BAB
    const bab = classDef ? baseBAB(classDef.bab) : 0

    // Size modifier: Small creatures get +1 to attack and AC
    const sizeMod = race?.size === 'Small' ? 1 : 0

    // Attack bonuses
    const meleeAttack = bab + mods.strength + sizeMod
    const rangedAttack = bab + mods.dexterity + sizeMod

    // AC = 10 + DEX mod + size mod (no armor yet)
    const ac = 10 + mods.dexterity + sizeMod

    // Speed
    const speed = race?.speed ?? 30

    // Hit Die
    const hitDie = classDef?.hitDie ?? 0

    // Skills
    const skills = PATHFINDER_SKILLS.map(skill => {
      let total = abilityModifier(finalScores[skill.keyAbility])

      // Racial skill bonuses
      if (race) {
        const raceBonus = race.skillBonuses.find(b => b.skill === skill.name)
        if (raceBonus) total += raceBonus.bonus
      }

      return {
        name: skill.name,
        keyAbility: skill.keyAbility,
        abilityAbbr: ABILITY_ABBR[skill.keyAbility],
        trainedOnly: skill.trainedOnly,
        total,
      }
    })

    return {
      finalScores,
      mods,
      racialMods,
      fortitude,
      reflex,
      will,
      bab,
      meleeAttack,
      rangedAttack,
      ac,
      speed,
      hitDie,
      skills,
      raceName: race?.name ?? null,
      className: classDef?.name ?? null,
    }
  }, [adventure])

  // ---- Roll handlers ----

  const doRoll = useCallback((label: string, modifier: number, modifierLabel?: string) => {
    const result = rollD20(modifier)
    setRollDisplay({ label, result, modifierLabel })
  }, [])

  const rollMeleeAttack = useCallback(() => {
    if (!derivedStats) return
    doRoll('Melee Attack', derivedStats.meleeAttack, `BAB ${formatMod(derivedStats.bab)} + STR ${formatMod(derivedStats.mods.strength)}`)
  }, [derivedStats, doRoll])

  const rollRangedAttack = useCallback(() => {
    if (!derivedStats) return
    doRoll('Ranged Attack', derivedStats.rangedAttack, `BAB ${formatMod(derivedStats.bab)} + DEX ${formatMod(derivedStats.mods.dexterity)}`)
  }, [derivedStats, doRoll])

  const rollFort = useCallback(() => {
    if (!derivedStats) return
    doRoll('Fortitude Save', derivedStats.fortitude, `Fort ${formatMod(derivedStats.fortitude)}`)
  }, [derivedStats, doRoll])

  const rollRef = useCallback(() => {
    if (!derivedStats) return
    doRoll('Reflex Save', derivedStats.reflex, `Ref ${formatMod(derivedStats.reflex)}`)
  }, [derivedStats, doRoll])

  const rollWill = useCallback(() => {
    if (!derivedStats) return
    doRoll('Will Save', derivedStats.will, `Will ${formatMod(derivedStats.will)}`)
  }, [derivedStats, doRoll])

  const rollInitiative = useCallback(() => {
    if (!derivedStats) return
    doRoll('Initiative', derivedStats.mods.dexterity, `DEX ${formatMod(derivedStats.mods.dexterity)}`)
  }, [derivedStats, doRoll])

  const rollAbility = useCallback((attr: AttributeType) => {
    if (!derivedStats) return
    const mod = derivedStats.mods[attr]
    doRoll(`${ABILITY_ABBR[attr]} Check`, mod, `${ABILITY_ABBR[attr]} ${formatMod(mod)}`)
  }, [derivedStats, doRoll])

  const rollSkill = useCallback((skillName: string, total: number) => {
    doRoll(`${skillName} Check`, total, `Skill ${formatMod(total)}`)
  }, [doRoll])

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

  if (error || !adventure || !derivedStats) {
    return (
      <div className="app">
        <Navbar />
        <p className="feedback-error">{error || 'Adventure not found'}</p>
      </div>
    )
  }

  const { character_snapshot, story, story_state } = adventure
  const stats = derivedStats

  return (
    <div className="app">
      <Navbar />
      <div className="adventure-play">
        {/* LEFT COLUMN — Character */}
        <div className="adventure-column character-column">
          <h2>{character_snapshot.name}</h2>
          {(stats.raceName || stats.className) && (
            <p className="char-subtitle">
              {[stats.raceName, stats.className].filter(Boolean).join(' ')}
            </p>
          )}

          {/* Always-visible combat stats */}
          <div className="combat-stats">
            <div className="combat-stat">
              <span className="stat-label">AC</span>
              <span className="stat-value">{stats.ac}</span>
            </div>
            <div className="combat-stat">
              <span className="stat-label">HP</span>
              <span className="stat-value">{adventure.character_hp} / {adventure.character_max_hp}</span>
            </div>
            <div className="combat-stat">
              <span className="stat-label">BAB</span>
              <span className="stat-value">{formatMod(stats.bab)}</span>
            </div>
            <div className="combat-stat">
              <span className="stat-label">Speed</span>
              <span className="stat-value">{stats.speed} ft</span>
            </div>
          </div>

          <div className="saves-row">
            <button className="save-item rollable" onClick={rollFort} title="Roll Fortitude Save">
              <span className="save-label">Fort</span>
              <span className="save-value">{formatMod(stats.fortitude)}</span>
              <span className="roll-dice-hint">🎲</span>
            </button>
            <button className="save-item rollable" onClick={rollRef} title="Roll Reflex Save">
              <span className="save-label">Ref</span>
              <span className="save-value">{formatMod(stats.reflex)}</span>
              <span className="roll-dice-hint">🎲</span>
            </button>
            <button className="save-item rollable" onClick={rollWill} title="Roll Will Save">
              <span className="save-label">Will</span>
              <span className="save-value">{formatMod(stats.will)}</span>
              <span className="roll-dice-hint">🎲</span>
            </button>
          </div>

          <div className="adventure-gold">
            <span className="stat-label">Gold</span>
            <span className="stat-value gold">{adventure.character_gold}</span>
          </div>

          {/* Collapsible toggle */}
          <div className="section-toggle">
            <button
              className={showSection === 'attributes' ? 'active' : ''}
              onClick={() => setShowSection('attributes')}
            >
              Attributes
            </button>
            <button
              className={showSection === 'skills' ? 'active' : ''}
              onClick={() => setShowSection('skills')}
            >
              Skills
            </button>
          </div>

          {/* Attributes section */}
          {showSection === 'attributes' && (
            <div className="attributes-list">
              {ATTRIBUTE_LABELS.map(attr => {
                const base = character_snapshot[attr]
                const racial = stats.racialMods[attr]
                const final = stats.finalScores[attr]
                const mod = stats.mods[attr]
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
          )}

          {/* Skills section */}
          {showSection === 'skills' && (
            <div className="skills-list-adventure">
              {stats.skills.map(skill => (
                <div
                  key={skill.name}
                  className={`skill-row ${skill.trainedOnly ? 'trained-only' : ''}`}
                >
                  <span className="skill-name">
                    {skill.name}
                    {skill.trainedOnly && <span className="badge-t">T</span>}
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
          )}

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
