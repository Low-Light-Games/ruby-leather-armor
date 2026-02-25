import { useState, useMemo, useCallback } from 'react';
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
import {
  getAllFeats,
  getFeatById,
  computeBAB,
  computeBaseSave,
  checkAllPrerequisites,
  canSelectFeat,
  computeFeatSkillBonuses,
  computeFeatStatBonuses,
  parseFeatEntry,
  buildFeatEntry,
  featDisplayName,
} from '../../rules/pathfinder_feats';
import type { FeatDefinition, PrerequisiteContext, PrerequisiteCheck } from '../../rules/pathfinder_feats';
import {
  getAllSpells,
  getSpellById,
  getSpellsForClass,
  isSpellcaster,
  castingStartLevel,
  maxSpellLevelForClass,
  checkSpellEligibility,
  canSelectSpell,
  getCastingStyle,
  computeSpellSlots,
  hasSlotForSpell,
} from '../../rules/pathfinder_spells';
import type { SpellDefinition } from '../../rules/pathfinder_spells_types';
import type { SpellEligibility, SpellSlotSummary } from '../../rules/pathfinder_spells';
import './SkillsColumn.scss';

// ─── Choice lists for parameterised feats ─────────────────

const SKILL_CHOICES = PATHFINDER_SKILLS.map(s => s.name);

const WEAPON_CHOICES = [
  'Bastard Sword', 'Battle Axe', 'Club', 'Composite Longbow', 'Composite Shortbow',
  'Dagger', 'Dart', 'Dwarven Waraxe', 'Elven Curve Blade', 'Falchion',
  'Flail', 'Glaive', 'Gnome Hooked Hammer', 'Greataxe', 'Greatclub',
  'Greatsword', 'Guisarme', 'Halberd', 'Handaxe', 'Hand Crossbow',
  'Heavy Crossbow', 'Heavy Flail', 'Heavy Mace', 'Heavy Pick', 'Heavy Shield',
  'Javelin', 'Kama', 'Kukri', 'Lance', 'Light Crossbow',
  'Light Flail', 'Light Hammer', 'Light Mace', 'Light Pick', 'Light Shield',
  'Longbow', 'Longsword', 'Longspear', 'Morningstar', 'Net',
  'Nunchaku', 'Orc Double Axe', 'Quarterstaff', 'Ranseur', 'Rapier',
  'Sai', 'Scimitar', 'Scythe', 'Short Sword', 'Shortbow',
  'Shortspear', 'Shuriken', 'Siangham', 'Sickle', 'Sling',
  'Spear', 'Spiked Chain', 'Starknife', 'Trident', 'Unarmed Strike',
  'War Hammer', 'Whip',
];

const SPELL_SCHOOL_CHOICES = [
  'Abjuration', 'Conjuration', 'Divination', 'Enchantment',
  'Evocation', 'Illusion', 'Necromancy', 'Transmutation',
];

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
  const {
    finalAttributes, currentRace, currentClass, currentLevel,
    selectedFeats, setSelectedFeats,
    selectedSpells, setSelectedSpells,
  } = useSheetsContext();

  const [openSections, setOpenSections] = useState<Record<string, boolean>>({
    combat: true,
    skills: true,
    feats: false,
    spells: false,
  });

  const [featSearch, setFeatSearch] = useState('');
  const [spellSearch, setSpellSearch] = useState('');

  // ─── Feat choice modal state ───────────────────────────────
  const [featChoiceModal, setFeatChoiceModal] = useState<{
    feat: FeatDefinition;
    choiceType: 'skill' | 'weapon' | 'school';
  } | null>(null);
  const [featChoiceSearch, setFeatChoiceSearch] = useState('');

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

  // Feat stat bonuses (AC, saves, initiative, HP, etc.)
  const featStatBonuses = useMemo(
    () => computeFeatStatBonuses(selectedFeats, currentLevel),
    [selectedFeats, currentLevel],
  );

  // Combat derived stats (including feat bonuses)
  const combatStats = useMemo(() => {
    const dexMod = abilityModifier(finalAttributes.dexterity);
    const strMod = abilityModifier(finalAttributes.strength);
    const conMod = abilityModifier(finalAttributes.constitution);
    const wisMod = abilityModifier(finalAttributes.wisdom);
    const size = race?.size ?? 'Medium';
    const bab = classDef ? computeBAB(classDef.bab, currentLevel) : 0;

    const ac = 10 + dexMod + acSizeModifier(size) + featStatBonuses.ac;
    const tAC = touchAC(dexMod, size) + featStatBonuses.ac;
    const ffAC = flatFootedAC(size); // Dodge AC doesn't apply when flat-footed
    const cmb = combatManeuverBonus(bab, strMod, size);
    const cmd = combatManeuverDefense(bab, strMod, dexMod, size);
    const initiative = dexMod + featStatBonuses.initiative;

    // Saves (base scaled by level + ability mod + feat bonuses)
    const fortGood = classDef ? classDef.goodSaves.includes('fort') : false;
    const refGood = classDef ? classDef.goodSaves.includes('ref') : false;
    const willGood = classDef ? classDef.goodSaves.includes('will') : false;
    const fort = computeBaseSave(fortGood, currentLevel) + conMod + featStatBonuses.fortSave;
    const ref = computeBaseSave(refGood, currentLevel) + dexMod + featStatBonuses.refSave;
    const will = computeBaseSave(willGood, currentLevel) + wisMod + featStatBonuses.willSave;

    // HP bonus from feats (e.g. Toughness)
    const hpBonus = featStatBonuses.hp;

    return { ac, tAC, ffAC, cmb, cmd, bab, initiative, fort, ref, will, hpBonus };
  }, [finalAttributes, race, classDef, currentLevel, featStatBonuses]);

  // ─── Prerequisite context ────────────────────────────────────

  const prereqContext = useMemo((): PrerequisiteContext => {
    const bab = classDef ? computeBAB(classDef.bab, currentLevel) : 0;
    return {
      finalAttributes,
      level: currentLevel,
      classId: currentClass,
      bab,
      ownedFeatIds: new Set(selectedFeats),
    };
  }, [finalAttributes, currentLevel, currentClass, classDef, selectedFeats]);

  // ─── Feats helpers ──────────────────────────────────────────

  /** Called when user picks a feat from the dropdown. If it has a choiceType, opens the modal; otherwise adds directly. */
  const addFeat = useCallback((featId: string) => {
    const feat = getAllFeats().find(f => f.id === featId);
    if (!feat) return;

    if (feat.choiceType) {
      // Open the choice modal
      setFeatChoiceModal({ feat, choiceType: feat.choiceType });
      setFeatChoiceSearch('');
      setFeatSearch('');
      return;
    }

    // Non-parameterised feat — add directly
    setSelectedFeats(prev => prev.includes(featId) ? prev : [...prev, featId]);
    setFeatSearch('');
  }, [setSelectedFeats]);

  /** Called from the choice modal to finalize a parameterised feat selection. */
  const confirmFeatChoice = useCallback((choice: string) => {
    if (!featChoiceModal) return;
    const entry = buildFeatEntry(featChoiceModal.feat.id, choice);
    setSelectedFeats(prev => prev.includes(entry) ? prev : [...prev, entry]);
    setFeatChoiceModal(null);
    setFeatChoiceSearch('');
  }, [featChoiceModal, setSelectedFeats]);

  const removeFeat = useCallback((featId: string) => {
    setSelectedFeats(prev => prev.filter(id => id !== featId));
  }, [setSelectedFeats]);

  const filteredFeats = useMemo(() => {
    const term = featSearch.toLowerCase().trim();
    if (!term) return [];
    return getAllFeats()
      .filter(f => !selectedFeats.includes(f.id))
      .filter(f => f.name.toLowerCase().includes(term) || f.category.includes(term))
      .slice(0, 12);
  }, [featSearch, selectedFeats]);

  /** Filtered feats with prerequisite checks attached. */
  const filteredFeatsWithChecks = useMemo(() => {
    return filteredFeats.map(feat => {
      const checks = checkAllPrerequisites(feat, prereqContext);
      const selectable = canSelectFeat(checks);
      return { feat, checks, selectable };
    });
  }, [filteredFeats, prereqContext]);

  /** Selected feats with parsed entries — includes the choice for compound IDs. */
  const selectedFeatsParsed = useMemo(
    () => selectedFeats.map(entry => {
      const parsed = parseFeatEntry(entry);
      const def = getAllFeats().find(f => f.id === parsed.featId);
      return { ...parsed, def };
    }).filter(e => e.def != null) as Array<{ featId: string; choice: string | null; raw: string; def: FeatDefinition }>,
    [selectedFeats],
  );

  // ─── Spells helpers ─────────────────────────────────────────

  const addSpell = useCallback((spellId: string) => {
    setSelectedSpells(prev => prev.includes(spellId) ? prev : [...prev, spellId]);
    setSpellSearch('');
  }, [setSelectedSpells]);

  const removeSpell = useCallback((spellId: string) => {
    setSelectedSpells(prev => prev.filter(id => id !== spellId));
  }, [setSelectedSpells]);

  /** How this class acquires spells. */
  const castingStyle = useMemo(() => getCastingStyle(currentClass), [currentClass]);

  /** Whether the current class has any spellcasting at all. */
  const classCasts = useMemo(() => isSpellcaster(currentClass), [currentClass]);

  /** The character level where this class first gains spells (null for non-casters). */
  const classStartLevel = useMemo(() => castingStartLevel(currentClass), [currentClass]);

  /** True if the character is high enough level to actually cast. */
  const castingUnlocked = useMemo(() => {
    if (!currentClass || !classCasts) return false;
    return maxSpellLevelForClass(currentClass, currentLevel) >= 0;
  }, [currentClass, classCasts, currentLevel]);

  /** Highest spell level the character can currently access (-1 if none). */
  const currentMaxSpellLevel = useMemo(
    () => maxSpellLevelForClass(currentClass, currentLevel),
    [currentClass, currentLevel],
  );

  /** Per-spell-level slot summary (for spontaneous & spellbook casters). */
  const spellSlots = useMemo<SpellSlotSummary[]>(
    () => computeSpellSlots(currentClass, currentLevel, finalAttributes.intelligence, selectedSpells),
    [currentClass, currentLevel, finalAttributes.intelligence, selectedSpells],
  );

  /** Section label changes by casting style. */
  const spellSectionLabel = useMemo(() => {
    switch (castingStyle) {
      case 'spellbook': return 'Spellbook';
      case 'spontaneous': return 'Known Spells';
      case 'prepared_list': return 'Spells';
      default: return 'Spells';
    }
  }, [castingStyle]);

  /**
   * Base pool of spells to search through.
   * - No class selected → all spells (browse mode).
   * - Non-caster → empty (they'll see a message instead).
   * - Caster → all class spells; eligibility + slot check handles locking.
   */
  const availableSpells = useMemo(() => {
    if (!currentClass) return getAllSpells();
    if (!classCasts) return [];
    return getSpellsForClass(currentClass, 9);
  }, [currentClass, classCasts]);

  /** Filtered spells with eligibility + slot checks attached. */
  const filteredSpellsWithChecks = useMemo(() => {
    const term = spellSearch.toLowerCase().trim();
    if (!term) return [];
    return availableSpells
      .filter(s => !selectedSpells.includes(s.id))
      .filter(s => s.name.toLowerCase().includes(term) || s.school.includes(term))
      .map(spell => {
        const eligibility = checkSpellEligibility(currentClass, currentLevel, spell);
        const eligible = canSelectSpell(eligibility);
        const hasSlot = eligible
          ? hasSlotForSpell(currentClass, currentLevel, finalAttributes.intelligence, spell, selectedSpells)
          : false;
        const selectable = eligible && hasSlot;
        const slotReason = eligible && !hasSlot ? 'Spell slots full for this level' : undefined;
        return { spell, eligibility, selectable, slotReason };
      })
      .slice(0, 12);
  }, [spellSearch, selectedSpells, availableSpells, currentClass, currentLevel, finalAttributes.intelligence]);

  const selectedSpellDefs = useMemo(
    () => selectedSpells.map(id => getSpellById(id)).filter(Boolean) as SpellDefinition[],
    [selectedSpells],
  );

  /** Eligibility of each already-selected spell (to warn when class changes). */
  const selectedSpellEligibilities = useMemo(() => {
    return selectedSpellDefs.map(spell => ({
      spell,
      eligibility: checkSpellEligibility(currentClass, currentLevel, spell),
    }));
  }, [selectedSpellDefs, currentClass, currentLevel]);

  // Feat-granted skill bonuses
  const featSkillBonuses = useMemo(
    () => computeFeatSkillBonuses(selectedFeats),
    [selectedFeats],
  );

  // Skills
  const calculatedSkills = useMemo(() => {
    return PATHFINDER_SKILLS.map(skill => {
      const abilityScore = finalAttributes[skill.keyAbility];
      const abilityMod = abilityModifier(abilityScore);
      const racialBonus = racialSkillBonuses[skill.name] || 0;
      const featBonus = featSkillBonuses[skill.name] || 0;
      const total = abilityMod + racialBonus + featBonus;
      return {
        ...skill,
        abilityAbbr: ABILITY_ABBREVIATIONS[skill.keyAbility],
        abilityMod,
        racialBonus,
        featBonus,
        total,
      };
    });
  }, [finalAttributes, racialSkillBonuses, featSkillBonuses]);

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
                <span className="combat-label">BAB</span>
                <span className="combat-value">{formatModifier(combatStats.bab)}</span>
              </div>
              <div className="combat-cell">
                <span className="combat-label">Init</span>
                <span className="combat-value">{formatModifier(combatStats.initiative)}</span>
              </div>
              <div className="combat-cell">
                <span className="combat-label">CMB</span>
                <span className="combat-value">{formatModifier(combatStats.cmb)}</span>
              </div>
              <div className="combat-cell">
                <span className="combat-label">CMD</span>
                <span className="combat-value">{combatStats.cmd}</span>
              </div>
              <div className="combat-cell">
                <span className="combat-label">Fort</span>
                <span className="combat-value">{formatModifier(combatStats.fort)}</span>
              </div>
              <div className="combat-cell">
                <span className="combat-label">Ref</span>
                <span className="combat-value">{formatModifier(combatStats.ref)}</span>
              </div>
              <div className="combat-cell">
                <span className="combat-label">Will</span>
                <span className="combat-value">{formatModifier(combatStats.will)}</span>
              </div>
              {combatStats.hpBonus > 0 && (
                <div className="combat-cell">
                  <span className="combat-label">HP (Feat)</span>
                  <span className="combat-value">+{combatStats.hpBonus}</span>
                </div>
              )}
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
              {Object.keys(featSkillBonuses).length > 0 && (
                <>&nbsp;&nbsp;<span className="feat-skill-badge">F</span> = Feat bonus</>
              )}
            </div>
          </div>
        )}
      </div>

      {/* Feats accordion */}
      <div className="accordion-section">
        <button className={`accordion-header ${openSections.feats ? 'open' : ''}`} onClick={() => toggleSection('feats')}>
          <span className="accordion-icon">{openSections.feats ? '▼' : '▶'}</span>
          Feats ({selectedFeats.length})
        </button>
        {openSections.feats && (
          <div className="accordion-body">
            <div className="picker-section">
              {/* Selected feats */}
              {selectedFeatsParsed.length > 0 ? (
                <div className="selected-items">
                  {selectedFeatsParsed.map(({ raw, choice, def: feat }) => (
                    <div key={raw} className="selected-item">
                      <div className="selected-item-header">
                        <span className="item-name">
                          {feat.name}
                          {choice && <span className="feat-choice-label"> ({choice})</span>}
                        </span>
                        <span className={`item-tag cat-${feat.category}`}>{feat.category}</span>
                        <button className="remove-btn" onClick={() => removeFeat(raw)} title="Remove feat">&times;</button>
                      </div>
                      <div className="selected-item-summary">{feat.summary}</div>
                    </div>
                  ))}
                </div>
              ) : (
                <p className="empty-text">No feats selected.</p>
              )}

              {/* Search / add */}
              <div className="picker-search">
                <input
                  type="text"
                  placeholder="Search feats…"
                  value={featSearch}
                  onChange={e => setFeatSearch(e.target.value)}
                  className="picker-input"
                />
                {filteredFeatsWithChecks.length > 0 && (
                  <ul className="picker-dropdown">
                    {filteredFeatsWithChecks.map(({ feat, checks, selectable }) => (
                      <li
                        key={feat.id}
                        className={`picker-option ${!selectable ? 'locked' : ''}`}
                        onClick={() => selectable && addFeat(feat.id)}
                      >
                        <div className="option-header">
                          {!selectable && <span className="lock-icon">🔒</span>}
                          <span className="option-name">{feat.name}</span>
                          <span className={`item-tag cat-${feat.category}`}>{feat.category}</span>
                        </div>
                        <div className="option-summary">{feat.summary}</div>
                        {checks.length > 0 && (
                          <div className="option-prereqs">
                            <PrereqList checks={checks} />
                          </div>
                        )}
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            </div>
          </div>
        )}
      </div>

      {/* Spells accordion */}
      <div className="accordion-section">
        <button className={`accordion-header ${openSections.spells ? 'open' : ''}`} onClick={() => toggleSection('spells')}>
          <span className="accordion-icon">{openSections.spells ? '▼' : '▶'}</span>
          {spellSectionLabel} ({selectedSpells.length})
        </button>
        {openSections.spells && (
          <div className="accordion-body">
            {/* Non-caster notice */}
            {currentClass && !classCasts && (
              <div className="casting-notice no-casting">
                <span className="notice-icon">🚫</span>
                <span>{classDef?.name ?? 'This class'} cannot cast spells.</span>
              </div>
            )}

            {/* Casting not yet unlocked (e.g. Paladin below level 4) */}
            {currentClass && classCasts && !castingUnlocked && (
              <div className="casting-notice not-yet">
                <span className="notice-icon">⏳</span>
                <span>Spellcasting begins at level {classStartLevel}. (Currently level {currentLevel})</span>
              </div>
            )}

            {/* Prepared full-list casters (cleric, druid, paladin, ranger) */}
            {currentClass && castingStyle === 'prepared_list' && castingUnlocked && (
              <div className="casting-notice prepared-list">
                <span className="notice-icon">📖</span>
                <span>
                  {classDef?.name} knows all class spells automatically.
                  Daily spell preparation will be available during adventures.
                </span>
              </div>
            )}

            {/* Active spellcasting: spontaneous or spellbook */}
            {(!currentClass || (castingUnlocked && (castingStyle === 'spontaneous' || castingStyle === 'spellbook'))) && (
              <div className="picker-section">
                {!currentClass && (
                  <p className="empty-text">No class selected — browsing all spells.</p>
                )}

                {/* Casting style description */}
                {currentClass && castingUnlocked && (
                  <div className="casting-style-info">
                    {castingStyle === 'spontaneous' && (
                      <p className="style-desc">
                        {classDef?.name} — spontaneous caster
                        ({classDef?.spellcasting?.ability.toUpperCase()}).
                        Select your limited known spells below.
                      </p>
                    )}
                    {castingStyle === 'spellbook' && (
                      <p className="style-desc">
                        {classDef?.name} — spellbook caster (INT).
                        Build your starting spellbook below.
                        {currentMaxSpellLevel === 0 ? ' Cantrips are added automatically.' : ''}
                      </p>
                    )}
                  </div>
                )}

                {/* Slot counters */}
                {spellSlots.length > 0 && (
                  <div className="spell-slot-bar">
                    {spellSlots.map(slot => (
                      <div
                        key={slot.spellLevel}
                        className={`slot-counter ${slot.remaining === 0 && slot.limit !== Infinity ? 'slot-full' : ''}`}
                      >
                        <span className="slot-label">{slot.label}</span>
                        <span className="slot-fraction">
                          {slot.limit === Infinity
                            ? `${slot.used} (auto)`
                            : `${slot.used}/${slot.limit}`}
                        </span>
                      </div>
                    ))}
                  </div>
                )}

                {/* Selected spells — with eligibility warnings */}
                {selectedSpellEligibilities.length > 0 ? (
                  <div className="selected-items">
                    {selectedSpellEligibilities.map(({ spell, eligibility }) => {
                      const lvl = eligibility.spellLevel ?? (currentClass ? spell.classLevels[currentClass.toLowerCase()] : Object.values(spell.classLevels)[0]);
                      const warn = eligibility.status !== 'available';
                      return (
                        <div key={spell.id} className={`selected-item spell-selected ${warn ? 'spell-warning' : ''}`}>
                          <div className="selected-item-header">
                            <span className="spell-level-badge">{lvl ?? '?'}</span>
                            <span className="item-name">{spell.name}</span>
                            <span className="item-tag school-tag">{spell.school}</span>
                            <button className="remove-btn" onClick={() => removeSpell(spell.id)} title="Remove spell">&times;</button>
                          </div>
                          <div className="selected-item-summary">{spell.summary}</div>
                          {warn && eligibility.reason && (
                            <div className="spell-eligibility-warn">⚠ {eligibility.reason}</div>
                          )}
                        </div>
                      );
                    })}
                  </div>
                ) : (
                  <p className="empty-text">
                    {castingStyle === 'spellbook' ? 'No spells in spellbook yet.' :
                     castingStyle === 'spontaneous' ? 'No known spells yet.' :
                     'No spells selected.'}
                  </p>
                )}

                {/* Search / add */}
                <div className="picker-search">
                  <input
                    type="text"
                    placeholder={
                      castingStyle === 'spellbook' ? `Add spells to spellbook…` :
                      castingStyle === 'spontaneous' ? `Search ${classDef?.name || ''} spells…` :
                      currentClass ? `Search ${classDef?.name || ''} spells…` : 'Search all spells…'
                    }
                    value={spellSearch}
                    onChange={e => setSpellSearch(e.target.value)}
                    className="picker-input"
                  />
                  {filteredSpellsWithChecks.length > 0 && (
                    <ul className="picker-dropdown">
                      {filteredSpellsWithChecks.map(({ spell, eligibility, selectable, slotReason }) => {
                        const lvl = eligibility.spellLevel ?? '?';
                        const reason = !selectable
                          ? (slotReason || eligibility.reason || '')
                          : '';
                        return (
                          <li
                            key={spell.id}
                            className={`picker-option ${!selectable ? 'locked' : ''}`}
                            onClick={() => selectable && addSpell(spell.id)}
                          >
                            <div className="option-header">
                              {!selectable && <span className="lock-icon">🔒</span>}
                              <span className={`spell-level-badge small ${!selectable ? 'badge-locked' : ''}`}>{lvl}</span>
                              <span className="option-name">{spell.name}</span>
                              <span className="item-tag school-tag">{spell.school}</span>
                            </div>
                            <div className="option-summary">{spell.summary}</div>
                            {reason && (
                              <div className="option-prereqs">
                                <span className="prereq-labels">
                                  <span className="prereq-chip prereq-unmet">✗ {reason}</span>
                                </span>
                              </div>
                            )}
                          </li>
                        );
                      })}
                    </ul>
                  )}
                </div>
              </div>
            )}
          </div>
        )}
      </div>

      {/* ─── Feat Choice Modal ─── */}
      {featChoiceModal && (
        <FeatChoiceModal
          feat={featChoiceModal.feat}
          choiceType={featChoiceModal.choiceType}
          search={featChoiceSearch}
          onSearchChange={setFeatChoiceSearch}
          onConfirm={confirmFeatChoice}
          onCancel={() => { setFeatChoiceModal(null); setFeatChoiceSearch(''); }}
          alreadySelected={selectedFeats}
        />
      )}
    </div>
  );
};

// ─── Feat Choice Modal Component ────────────────────────────

interface FeatChoiceModalProps {
  feat: FeatDefinition;
  choiceType: 'skill' | 'weapon' | 'school';
  search: string;
  onSearchChange: (val: string) => void;
  onConfirm: (choice: string) => void;
  onCancel: () => void;
  alreadySelected: string[];
}

function FeatChoiceModal({ feat, choiceType, search, onSearchChange, onConfirm, onCancel, alreadySelected }: FeatChoiceModalProps) {
  const allChoices = choiceType === 'skill' ? SKILL_CHOICES
    : choiceType === 'weapon' ? WEAPON_CHOICES
    : SPELL_SCHOOL_CHOICES;

  // Choices already taken for this repeatable feat
  const takenChoices = useMemo(() => {
    const taken = new Set<string>();
    for (const entry of alreadySelected) {
      const parsed = parseFeatEntry(entry);
      if (parsed.featId === feat.id && parsed.choice) {
        taken.add(parsed.choice);
      }
    }
    return taken;
  }, [alreadySelected, feat.id]);

  const filtered = useMemo(() => {
    const term = search.toLowerCase().trim();
    return allChoices
      .filter(c => !takenChoices.has(c))
      .filter(c => !term || c.toLowerCase().includes(term));
  }, [allChoices, takenChoices, search]);

  const title = choiceType === 'skill' ? 'Choose a Skill'
    : choiceType === 'weapon' ? 'Choose a Weapon'
    : 'Choose a Spell School';

  return (
    <div className="feat-choice-overlay" onClick={onCancel}>
      <div className="feat-choice-modal" onClick={e => e.stopPropagation()}>
        <div className="fcm-header">
          <h3>{feat.name}</h3>
          <button className="fcm-close" onClick={onCancel}>&times;</button>
        </div>
        <p className="fcm-subtitle">{title}</p>
        <p className="fcm-description">{feat.summary}</p>
        <input
          type="text"
          className="fcm-search"
          placeholder={`Search ${choiceType}s…`}
          value={search}
          onChange={e => onSearchChange(e.target.value)}
          autoFocus
        />
        <ul className="fcm-list">
          {filtered.map(choice => (
            <li key={choice} className="fcm-item" onClick={() => onConfirm(choice)}>
              {choice}
            </li>
          ))}
          {filtered.length === 0 && (
            <li className="fcm-empty">No matching {choiceType}s found.</li>
          )}
        </ul>
      </div>
    </div>
  );
}

/** Renders a compact list of prerequisite labels with met/unmet/unknown color coding. */
function PrereqList({ checks }: { checks: PrerequisiteCheck[] }) {
  return (
    <span className="prereq-labels">
      <span className="prereq-prefix">Requires:</span>
      {checks.map((c, i) => (
        <span key={i} className={`prereq-chip prereq-${c.status}`}>
          {c.status === 'met' && '✓ '}
          {c.status === 'unmet' && '✗ '}
          {c.status === 'unknown' && '? '}
          {c.label}
        </span>
      ))}
    </span>
  );
}

export default SkillsColumn;
