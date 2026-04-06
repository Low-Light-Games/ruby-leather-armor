import React from 'react'
import { Accordion } from '../../ui/Accordion'
import type { AdventureSheet, DerivedStats } from '../../../types'
import type { ClassDefinition } from '../../../rules/pathfinder_classes'
import type { SkillRanksMap } from '../../../rules/pathfinder_skill_ranks'
import { formatMod } from '../../../utils/formatting'
import { maxRanksForSkill, rankPointCost } from '../../../rules/pathfinder_skill_ranks'
import { SkillRankStepper } from '../../SkillsColumn/skills/SkillRankStepper'

export interface SkillsAccordionProps {
  isOpen: boolean
  onToggle: () => void
  sheet: AdventureSheet
  ds: DerivedStats
  classDef: ClassDefinition | undefined
  ranksMap: SkillRanksMap
  pointsSummary: { spent: number; total: number; remaining: number } | null
  handleRankDelta: (skillName: string, delta: 1 | -1) => void | Promise<void>
  rankSaving: boolean
  rankErrors: string[]
  dismissRankErrors: () => void
  rollSkill: (skillName: string, total: number) => void
}

const SkillsAccordion: React.FC<SkillsAccordionProps> = ({
  isOpen,
  onToggle,
  sheet,
  ds,
  classDef,
  ranksMap,
  pointsSummary,
  handleRankDelta,
  rankSaving,
  rankErrors,
  dismissRankErrors,
  rollSkill,
}) => (
  <Accordion title="Skills" isOpen={isOpen} onToggle={onToggle}>
    {rankErrors.length > 0 && (
      <div className="skills-rank-errors" role="alert" aria-live="polite">
        <p className="skills-rank-errors__title">Could not save skill ranks:</p>
        <ul className="skills-rank-errors__list">
          {rankErrors.map((line, i) => (
            <li key={`${i}-${line.slice(0, 40)}`}>{line}</li>
          ))}
        </ul>
        <button
          type="button"
          className="skills-rank-errors__dismiss"
          onClick={dismissRankErrors}
        >
          Dismiss
        </button>
      </div>
    )}
    {!sheet.character_class && (
      <p className="skills-assign-hint-adventure">Choose a class to assign skill ranks.</p>
    )}
    {sheet.character_class && classDef && pointsSummary && (
      <div className="skills-points-bar-adventure" role="status">
        <span>Skill points</span>
        <span>
          {pointsSummary.spent} / {pointsSummary.total}
          {pointsSummary.remaining > 0 && (
            <span className="skills-points-remaining"> ({pointsSummary.remaining} left)</span>
          )}
        </span>
      </div>
    )}
    <div className="skills-list-adventure">
      {ds.skills.map(skill => {
        const rankStored = ranksMap[skill.name] ?? 0
        const rankMax = maxRanksForSkill(skill.name, sheet.character_class, sheet.level)
        const nextCost = sheet.character_class ? rankPointCost(skill.name, sheet.character_class) : 2
        const showRanks = Boolean(sheet.character_class && classDef)
        return (
          <div key={skill.name} className={`skill-row skill-row-adventure-skills ${skill.trained_only ? 'trained-only' : ''}`}>
            <span className="skill-name">
              {skill.name}
              {skill.trained_only && <span className="badge-t">T</span>}
            </span>
            {showRanks && (
              <span className="skill-rank-cell-adventure">
                <SkillRankStepper
                  value={rankStored}
                  onDelta={d => { void handleRankDelta(skill.name, d) }}
                  disabledMinus={rankStored <= 0 || rankSaving}
                  disabledPlus={
                    rankSaving ||
                    rankStored >= rankMax ||
                    !pointsSummary ||
                    pointsSummary.remaining < nextCost
                  }
                />
              </span>
            )}
            <span className={`skill-mod ${skill.total >= 0 ? 'positive' : 'negative'}`}>
              {formatMod(skill.total)}
            </span>
            <button className="roll-dice-btn" onClick={() => rollSkill(skill.name, skill.total)}
              title={`Roll ${skill.name} Check`} aria-label={`Roll ${skill.name} Check`}>
              🎲
            </button>
          </div>
        )
      })}
    </div>
  </Accordion>
)

export default SkillsAccordion
