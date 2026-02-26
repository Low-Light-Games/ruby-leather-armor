import React from 'react';
import type { CalculatedSkill } from '../hooks/useSkills';
import { formatMod } from '../../../utils/formatting';

interface SkillsSectionProps {
  skills: CalculatedSkill[];
  racialBonuses: Record<string, number>;
  featBonuses: Record<string, number>;
}

export const SkillsSection: React.FC<SkillsSectionProps> = ({ skills, racialBonuses, featBonuses }) => {
  return (
    <>
      <div className="skills-header">
        <span className="skills-header-name">Skill</span>
        <span className="skills-header-ability">Ability</span>
        <span className="skills-header-mod">Total</span>
      </div>
      <ul className="skills-list">
        {skills.map(skill => (
          <li
            key={skill.name}
            className={`skill-row ${skill.trainedOnly ? 'trained-only' : ''}`}
            title={
              [
                skill.name,
                skill.trainedOnly ? '(Trained only)' : '',
                `${skill.abilityAbbr} mod: ${formatMod(skill.abilityMod)}`,
                skill.racialBonus ? `Racial: +${skill.racialBonus}` : '',
                skill.featBonus ? `Feat: +${skill.featBonus}` : '',
              ].filter(Boolean).join(' | ')
            }
          >
            <span className="skill-name">
              {skill.name}
              {skill.trainedOnly && <span className="trained-badge">T</span>}
              {skill.racialBonus > 0 && <span className="racial-skill-badge">R</span>}
              {skill.featBonus > 0 && <span className="feat-skill-badge">F</span>}
            </span>
            <span className="skill-ability">{skill.abilityAbbr}</span>
            <span className={`skill-modifier ${skill.total >= 0 ? 'positive' : 'negative'}`}>
              {formatMod(skill.total)}
            </span>
          </li>
        ))}
      </ul>
      <div className="skills-legend">
        <span className="trained-badge">T</span> = Trained only
        {Object.keys(racialBonuses).length > 0 && (
          <>&nbsp;&nbsp;<span className="racial-skill-badge">R</span> = Racial bonus</>
        )}
        {Object.keys(featBonuses).length > 0 && (
          <>&nbsp;&nbsp;<span className="feat-skill-badge">F</span> = Feat bonus</>
        )}
      </div>
    </>
  );
};
