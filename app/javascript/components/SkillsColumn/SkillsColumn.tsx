import { useMemo } from 'react';
import { useSheetsContext } from '../../contexts/SheetsContext';
import { PATHFINDER_SKILLS, abilityModifier } from '../../rules/pathfinder_skills';
import { getRaceById } from '../../rules/pathfinder_races';
import './SkillsColumn.scss';

const ABILITY_ABBREVIATIONS: Record<string, string> = {
  strength: 'STR',
  dexterity: 'DEX',
  constitution: 'CON',
  intelligence: 'INT',
  wisdom: 'WIS',
  charisma: 'CHA',
};

function formatModifier(mod: number): string {
  return mod >= 0 ? `+${mod}` : `${mod}`;
}

export const SkillsColumn = () => {
  const { finalAttributes, currentRace } = useSheetsContext();

  const race = useMemo(() => currentRace ? getRaceById(currentRace) : undefined, [currentRace]);

  // Build a lookup of racial skill bonuses: skill name -> bonus
  const racialSkillBonuses = useMemo(() => {
    const map: Record<string, number> = {};
    if (race) {
      for (const sb of race.skillBonuses) {
        map[sb.skill] = (map[sb.skill] || 0) + sb.bonus;
      }
    }
    return map;
  }, [race]);

  const calculatedSkills = useMemo(() => {
    return PATHFINDER_SKILLS.map(skill => {
      const abilityScore = finalAttributes[skill.keyAbility];
      const abilityMod = abilityModifier(abilityScore);
      const racialBonus = racialSkillBonuses[skill.name] || 0;
      const total = abilityMod + racialBonus;
      return {
        ...skill,
        abilityAbbr: ABILITY_ABBREVIATIONS[skill.keyAbility],
        abilityMod,
        racialBonus,
        total,
      };
    });
  }, [finalAttributes, racialSkillBonuses]);

  return (
    <div className="skills-column">
      <div className="skills-header">
        <span className="skills-header-name">Skill</span>
        <span className="skills-header-ability">Ability</span>
        <span className="skills-header-mod">Total</span>
      </div>
      <ul className="skills-list">
        {calculatedSkills.map(skill => (
          <li
            key={skill.name}
            className={`skill-row ${skill.trainedOnly ? 'trained-only' : ''}`}
            title={
              [
                skill.name,
                skill.trainedOnly ? '(Trained only)' : '',
                `${skill.abilityAbbr} mod: ${formatModifier(skill.abilityMod)}`,
                skill.racialBonus ? `Racial: +${skill.racialBonus}` : '',
              ].filter(Boolean).join(' | ')
            }
          >
            <span className="skill-name">
              {skill.name}
              {skill.trainedOnly && <span className="trained-badge">T</span>}
              {skill.racialBonus > 0 && <span className="racial-skill-badge">R</span>}
            </span>
            <span className="skill-ability">{skill.abilityAbbr}</span>
            <span className={`skill-modifier ${skill.total >= 0 ? 'positive' : 'negative'}`}>
              {formatModifier(skill.total)}
            </span>
          </li>
        ))}
      </ul>
      <div className="skills-legend">
        <span className="trained-badge">T</span> = Trained only
        {Object.keys(racialSkillBonuses).length > 0 && (
          <>&nbsp;&nbsp;<span className="racial-skill-badge">R</span> = Racial bonus</>
        )}
      </div>
    </div>
  );
};

export default SkillsColumn;
