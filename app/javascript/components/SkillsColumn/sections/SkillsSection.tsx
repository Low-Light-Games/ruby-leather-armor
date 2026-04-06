import React from 'react';
import type { CalculatedSkill } from '../hooks/useSkills';
import type { SkillPointsSummary } from '../hooks/useSkillRanks';
import { formatMod } from '../../../utils/formatting';
import { SkillRankStepper } from '../skills/SkillRankStepper';

interface SkillsSectionProps {
  skills: CalculatedSkill[];
  racialBonuses: Record<string, number>;
  featBonuses: Record<string, number>;
  canAssignRanks: boolean;
  pointsSummary: SkillPointsSummary | null;
  onAdjustRank: (skillName: string, delta: 1 | -1) => void;
  /** Display name of the selected class (for hint copy); null when none. */
  selectedClassName: string | null;
}

export const SkillsSection: React.FC<SkillsSectionProps> = ({
  skills,
  racialBonuses,
  featBonuses,
  canAssignRanks,
  pointsSummary,
  onAdjustRank,
  selectedClassName,
}) => {
  return (
    <>
      {!canAssignRanks && (
        <p className="skills-assign-hint">
          Select a <strong>class</strong> in Character Sheet (left) to assign skill ranks and to see which
          skills are <strong>class skills</strong> for that class. Until then, totals below use ability
          modifiers only.
        </p>
      )}
      <div className={canAssignRanks ? undefined : 'skills-accordion-inner--no-class'}>
        {canAssignRanks && pointsSummary && (
          <div className="skills-points-bar" role="status">
            <span className="skills-points-label">Skill points</span>
            <span className="skills-points-values">
              {pointsSummary.spent} / {pointsSummary.total}
              {pointsSummary.remaining > 0 && (
                <span className="skills-points-remaining"> ({pointsSummary.remaining} left)</span>
              )}
            </span>
          </div>
        )}
        <div className={`skills-header${canAssignRanks ? ' skills-header-with-ranks' : ''}`}>
          <span className="skills-header-name">Skill</span>
          <span className="skills-header-ability">Ability</span>
          {canAssignRanks && <span className="skills-header-ranks">Ranks</span>}
          <span className="skills-header-mod">Total</span>
        </div>
        <ul className="skills-list">
          {skills.map(skill => (
            <li
              key={skill.name}
              className={`skill-row ${skill.trainedOnly ? 'trained-only' : ''}${canAssignRanks ? ' skill-row-with-ranks' : ''}${skill.isClassSkill ? ' skill-row--class-skill' : ''}`}
              title={
                [
                  skill.name,
                  skill.isClassSkill && selectedClassName
                    ? `Class skill (${selectedClassName})`
                    : skill.isClassSkill
                      ? 'Class skill'
                      : '',
                  skill.trainedOnly ? '(Trained only)' : '',
                  `${skill.abilityAbbr} mod: ${formatMod(skill.abilityMod)}`,
                  skill.rankRanks > 0 ? `Ranks: ${skill.rankRanks}` : '',
                  skill.racialBonus ? `Racial: +${skill.racialBonus}` : '',
                  skill.featBonus ? `Feat: +${skill.featBonus}` : '',
                ].filter(Boolean).join(' | ')
              }
            >
              <span className="skill-name">
                {skill.name}
                {skill.isClassSkill && (
                  <span className="class-skill-badge" title="Class skill for your selected class">
                    C
                  </span>
                )}
                {skill.trainedOnly && <span className="trained-badge">T</span>}
                {skill.racialBonus > 0 && <span className="racial-skill-badge">R</span>}
                {skill.featBonus > 0 && <span className="feat-skill-badge">F</span>}
              </span>
              <span className="skill-ability">{skill.abilityAbbr}</span>
              {canAssignRanks && (
                <span className="skill-rank-cell">
                  <SkillRankStepper
                    value={skill.rankStored}
                    onDelta={d => onAdjustRank(skill.name, d)}
                    disabledMinus={skill.rankStored <= 0}
                    disabledPlus={
                      !pointsSummary ||
                      skill.rankStored >= skill.rankMax ||
                      pointsSummary.remaining < skill.rankNextCost
                    }
                  />
                </span>
              )}
              <span className={`skill-modifier ${skill.total >= 0 ? 'positive' : 'negative'}`}>
                {formatMod(skill.total)}
              </span>
            </li>
          ))}
        </ul>
        <div className="skills-legend">
          {canAssignRanks && (
            <>
              <span className="class-skill-badge">C</span> = Class skill (1 pt/rank; higher max ranks)
              &nbsp;&nbsp;
            </>
          )}
          <span className="trained-badge">T</span> = Trained only
          {Object.keys(racialBonuses).length > 0 && (
            <>&nbsp;&nbsp;<span className="racial-skill-badge">R</span> = Racial bonus</>
          )}
          {Object.keys(featBonuses).length > 0 && (
            <>&nbsp;&nbsp;<span className="feat-skill-badge">F</span> = Feat bonus</>
          )}
          {canAssignRanks && <>&nbsp;&nbsp;Ranks adjust with − / + (cross-class skills cost 2 pts/rank).</>}
        </div>
      </div>
    </>
  );
};
