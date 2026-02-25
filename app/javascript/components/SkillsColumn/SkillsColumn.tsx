import { useState, useMemo } from 'react';
import { useSheetsContext } from '../../contexts/SheetsContext';
import { PATHFINDER_SKILLS, abilityModifier } from '../../rules/pathfinder_skills';
import { getRaceById } from '../../rules/pathfinder_races';
import { getClassById } from '../../rules/pathfinder_classes';
import {
  touchAC,
  flatFootedAC,
  combatManeuverBonus,
  combatManeuverDefense,
  acSizeModifier,
} from '../../rules/pathfinder_combat';
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

function baseBAB(bab: string): number {
  return bab === 'full' ? 1 : 0;
}

export const SkillsColumn = () => {
  const { finalAttributes, currentRace, currentClass } = useSheetsContext();

  const [openSections, setOpenSections] = useState<Record<string, boolean>>({
    combat: true,
    skills: true,
    feats: false,
    spells: false,
  });

  const toggleSection = (section: string) => {
    setOpenSections(prev => ({ ...prev, [section]: !prev[section] }));
  };

  const race = useMemo(() => currentRace ? getRaceById(currentRace) : undefined, [currentRace]);
  const classDef = useMemo(() => currentClass ? getClassById(currentClass) : undefined, [currentClass]);

  // Racial skill bonuses
  const racialSkillBonuses = useMemo(() => {
    const map: Record<string, number> = {};
    if (race) {
      for (const sb of race.skillBonuses) {
        map[sb.skill] = (map[sb.skill] || 0) + sb.bonus;
      }
    }
    return map;
  }, [race]);

  // Combat derived stats
  const combatStats = useMemo(() => {
    const dexMod = abilityModifier(finalAttributes.dexterity);
    const strMod = abilityModifier(finalAttributes.strength);
    const size = race?.size ?? 'Medium';
    const bab = classDef ? baseBAB(classDef.bab) : 0;

    const ac = 10 + dexMod + acSizeModifier(size);
    const tAC = touchAC(dexMod, size);
    const ffAC = flatFootedAC(size);
    const cmb = combatManeuverBonus(bab, strMod, size);
    const cmd = combatManeuverDefense(bab, strMod, dexMod, size);

    return { ac, tAC, ffAC, cmb, cmd };
  }, [finalAttributes, race, classDef]);

  // Skills
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
      {/* Combat Stats accordion */}
      <div className="accordion-section">
        <button className={`accordion-header ${openSections.combat ? 'open' : ''}`} onClick={() => toggleSection('combat')}>
          <span className="accordion-icon">{openSections.combat ? '▼' : '▶'}</span>
          Combat Stats
        </button>
        {openSections.combat && (
          <div className="accordion-body">
            <div className="combat-grid">
              <div className="combat-cell">
                <span className="combat-label">AC</span>
                <span className="combat-value">{combatStats.ac}</span>
              </div>
              <div className="combat-cell">
                <span className="combat-label">Touch AC</span>
                <span className="combat-value">{combatStats.tAC}</span>
              </div>
              <div className="combat-cell">
                <span className="combat-label">Flat-Footed</span>
                <span className="combat-value">{combatStats.ffAC}</span>
              </div>
              <div className="combat-cell">
                <span className="combat-label">CMB</span>
                <span className="combat-value">{formatModifier(combatStats.cmb)}</span>
              </div>
              <div className="combat-cell">
                <span className="combat-label">CMD</span>
                <span className="combat-value">{combatStats.cmd}</span>
              </div>
            </div>
          </div>
        )}
      </div>

      {/* Skills accordion */}
      <div className="accordion-section">
        <button className={`accordion-header ${openSections.skills ? 'open' : ''}`} onClick={() => toggleSection('skills')}>
          <span className="accordion-icon">{openSections.skills ? '▼' : '▶'}</span>
          Skills
        </button>
        {openSections.skills && (
          <div className="accordion-body">
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
        )}
      </div>

      {/* Feats accordion */}
      <div className="accordion-section">
        <button className={`accordion-header ${openSections.feats ? 'open' : ''}`} onClick={() => toggleSection('feats')}>
          <span className="accordion-icon">{openSections.feats ? '▼' : '▶'}</span>
          Feats
        </button>
        {openSections.feats && (
          <div className="accordion-body">
            <div className="placeholder-section">
              <p className="placeholder-text">No feats selected yet.</p>
              <div className="feat-placeholder">
                <div className="feat-item">
                  <span className="feat-name">Power Attack</span>
                  <span className="feat-type">Combat</span>
                </div>
                <div className="feat-item">
                  <span className="feat-name">Toughness</span>
                  <span className="feat-type">General</span>
                </div>
                <div className="feat-item disabled">
                  <span className="feat-name">Weapon Focus</span>
                  <span className="feat-type">Combat</span>
                </div>
              </div>
              <p className="placeholder-hint">Feat selection will be available in a future update.</p>
            </div>
          </div>
        )}
      </div>

      {/* Spells accordion */}
      <div className="accordion-section">
        <button className={`accordion-header ${openSections.spells ? 'open' : ''}`} onClick={() => toggleSection('spells')}>
          <span className="accordion-icon">{openSections.spells ? '▼' : '▶'}</span>
          Spells
        </button>
        {openSections.spells && (
          <div className="accordion-body">
            <div className="placeholder-section">
              <p className="placeholder-text">No spells prepared.</p>
              <div className="spell-placeholder">
                <div className="spell-item">
                  <span className="spell-level">0</span>
                  <span className="spell-name">Detect Magic</span>
                </div>
                <div className="spell-item">
                  <span className="spell-level">1</span>
                  <span className="spell-name">Magic Missile</span>
                </div>
                <div className="spell-item disabled">
                  <span className="spell-level">1</span>
                  <span className="spell-name">Shield</span>
                </div>
              </div>
              <p className="placeholder-hint">Spell management will be available in a future update.</p>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default SkillsColumn;
