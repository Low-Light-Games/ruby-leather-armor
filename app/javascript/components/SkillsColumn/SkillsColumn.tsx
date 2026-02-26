import { useState, useMemo, useCallback } from 'react';
import { useSheetsContext } from '../../contexts/SheetsContext';
import { PATHFINDER_SKILLS, abilityModifier } from '../../rules/pathfinder_skills';
import { getRaceById } from '../../rules/pathfinder_races';
import { getClassById } from '../../rules/pathfinder_classes';
import {
  touchAC,
  flatFootedAC,
  fullAC,
  combatManeuverBonus,
  combatManeuverDefense,
} from '../../rules/pathfinder_combat';
import {
  computeEquipmentBonuses,
  computeEquipmentStatBonuses,
  computeEquipmentSkillBonuses,
  computeTotalWeight,
  getCarryCapacity,
  computeEncumbranceTier,
  getEncumbranceLimits,
  effectiveDexMod as computeEffectiveDexMod,
  computeEffectiveSpeed,
} from '../../rules/pathfinder_items';
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
import type { FeatDefinition, PrerequisiteContext } from '../../rules/pathfinder_feats';
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
import type { SpellSlotSummary } from '../../rules/pathfinder_spells';
import { ABILITY_ABBR } from '../../utils/formatting';
import { Accordion } from './shared/Accordion';
import { CombatStatsSection } from './sections/CombatStatsSection';
import { SkillsSection } from './sections/SkillsSection';
import { FeatsSection } from './sections/FeatsSection';
import { SpellsSection } from './sections/SpellsSection';
import { EquipmentSection } from './sections/EquipmentSection';
import FeatChoiceModal from './FeatChoiceModal';
import './SkillsColumn.scss';

export const SkillsColumn = () => {
  const {
    finalAttributes, currentRace, currentClass, currentLevel,
    selectedFeats, setSelectedFeats,
    selectedSpells, setSelectedSpells,
    selectedItems, setSelectedItems,
    currentCurrency, setCurrentCurrency,
  } = useSheetsContext();

  const [openSections, setOpenSections] = useState<Record<string, boolean>>({
    combat: true,
    skills: true,
    equipment: false,
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

  // Equipment bonuses from equipped items
  const equipBonuses = useMemo(
    () => computeEquipmentBonuses(selectedItems),
    [selectedItems],
  );

  const equipStatBonuses = useMemo(
    () => computeEquipmentStatBonuses(selectedItems, currentLevel),
    [selectedItems, currentLevel],
  );

  const equipSkillBonuses = useMemo(
    () => computeEquipmentSkillBonuses(selectedItems),
    [selectedItems],
  );

  // Carry weight & encumbrance
  const totalWeight = useMemo(
    () => computeTotalWeight(selectedItems, currentCurrency),
    [selectedItems, currentCurrency],
  );

  const carryCapacity = useMemo(() => {
    const size = race?.size ?? 'Medium';
    return getCarryCapacity(finalAttributes.strength, size);
  }, [finalAttributes.strength, race]);

  const encumbranceTier = useMemo(
    () => computeEncumbranceTier(totalWeight, carryCapacity),
    [totalWeight, carryCapacity],
  );

  const encumbranceLimits = useMemo(
    () => getEncumbranceLimits(encumbranceTier),
    [encumbranceTier],
  );

  // Combat derived stats (including feat + equipment bonuses)
  const combatStats = useMemo(() => {
    const rawDexMod = abilityModifier(finalAttributes.dexterity);
    const strMod = abilityModifier(finalAttributes.strength);
    const conMod = abilityModifier(finalAttributes.constitution);
    const wisMod = abilityModifier(finalAttributes.wisdom);
    const size = race?.size ?? 'Medium';
    const bab = classDef ? computeBAB(classDef.bab, currentLevel) : 0;

    // Effective DEX mod (capped by armor + encumbrance)
    const effDexMod = computeEffectiveDexMod(
      rawDexMod,
      equipBonuses.maxDexBonus,
      encumbranceLimits.maxDex,
    );

    // AC with armor, shield, feats, and item effect bonuses
    const acBonuses = featStatBonuses.ac + equipStatBonuses.ac;
    const ac = fullAC(effDexMod, size, equipBonuses.armorBonus, equipBonuses.shieldBonus, acBonuses);
    const tAC = touchAC(effDexMod, size, acBonuses); // no armor/shield
    const ffAC = flatFootedAC(size, equipBonuses.armorBonus, equipBonuses.shieldBonus); // no DEX/dodge

    const cmb = combatManeuverBonus(bab, strMod, size);
    const cmd = combatManeuverDefense(bab, strMod, effDexMod, size);
    const initiative = effDexMod + featStatBonuses.initiative + equipStatBonuses.initiative;

    // Saves
    const fortGood = classDef ? classDef.goodSaves.includes('fort') : false;
    const refGood = classDef ? classDef.goodSaves.includes('ref') : false;
    const willGood = classDef ? classDef.goodSaves.includes('will') : false;
    const fort = computeBaseSave(fortGood, currentLevel) + conMod +
                 featStatBonuses.fortSave + equipStatBonuses.fortSave;
    const ref = computeBaseSave(refGood, currentLevel) + effDexMod +
                featStatBonuses.refSave + equipStatBonuses.refSave;
    const will = computeBaseSave(willGood, currentLevel) + wisMod +
                 featStatBonuses.willSave + equipStatBonuses.willSave;

    // HP bonus from feats + items
    const hpBonus = featStatBonuses.hp + equipStatBonuses.hp;

    // ACP from armor + encumbrance
    const totalACP = equipBonuses.armorCheckPenalty + encumbranceLimits.acp;

    // Speed
    const baseSpeed = race?.speed ?? 30;
    const speed = computeEffectiveSpeed(baseSpeed, equipBonuses, encumbranceTier);

    // Arcane spell failure
    const arcaneSpellFailure = equipBonuses.arcaneSpellFailure;

    return {
      ac, tAC, ffAC, cmb, cmd, bab, initiative, fort, ref, will, hpBonus,
      totalACP, speed, arcaneSpellFailure, encumbranceTier,
      armorBonus: equipBonuses.armorBonus,
      shieldBonus: equipBonuses.shieldBonus,
      totalWeight, carryCapacity,
    };
  }, [
    finalAttributes, race, classDef, currentLevel,
    featStatBonuses, equipBonuses, equipStatBonuses,
    encumbranceLimits, encumbranceTier, totalWeight, carryCapacity,
  ]);

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
        // When browsing (no class), all spells are selectable
        if (!currentClass) {
          return {
            spell,
            eligibility: { status: 'available' as const, spellLevel: Object.values(spell.classLevels)[0] ?? null },
            selectable: true,
            slotReason: undefined,
          };
        }
        // When a class is selected, check eligibility and slots
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

  // Total ACP for skill calculations
  const totalACP = useMemo(
    () => equipBonuses.armorCheckPenalty + encumbranceLimits.acp,
    [equipBonuses.armorCheckPenalty, encumbranceLimits.acp],
  );

  // Skills (with ACP and equipment bonuses)
  const calculatedSkills = useMemo(() => {
    return PATHFINDER_SKILLS.map(skill => {
      const abilityScore = finalAttributes[skill.keyAbility];
      const abilityMod = abilityModifier(abilityScore);
      const racialBonus = racialSkillBonuses[skill.name] || 0;
      const featBonus = featSkillBonuses[skill.name] || 0;
      const equipBonus = equipSkillBonuses[skill.name] || 0;
      const acpPenalty = skill.armorCheckPenalty ? totalACP : 0;
      const total = abilityMod + racialBonus + featBonus + equipBonus + acpPenalty;
      return {
        ...skill,
        abilityAbbr: ABILITY_ABBR[skill.keyAbility],
        abilityMod,
        racialBonus,
        featBonus,
        equipBonus,
        acpPenalty,
        total,
      };
    });
  }, [finalAttributes, racialSkillBonuses, featSkillBonuses, equipSkillBonuses, totalACP]);

  return (
    <div className="skills-column">
      <Accordion
        title="Combat Stats"
        isOpen={openSections.combat}
        onToggle={() => toggleSection('combat')}
      >
        <CombatStatsSection combatStats={combatStats} />
      </Accordion>

      <Accordion
        title="Skills"
        isOpen={openSections.skills}
        onToggle={() => toggleSection('skills')}
      >
        <SkillsSection
          skills={calculatedSkills}
          racialBonuses={racialSkillBonuses}
          featBonuses={featSkillBonuses}
        />
      </Accordion>

      <Accordion
        title={`Equipment (${selectedItems.length})`}
        isOpen={openSections.equipment}
        onToggle={() => toggleSection('equipment')}
      >
        <EquipmentSection
          selectedItems={selectedItems}
          setSelectedItems={setSelectedItems}
          currentCurrency={currentCurrency}
          setCurrentCurrency={setCurrentCurrency}
          currentClass={currentClass}
        />
      </Accordion>

      <Accordion
        title={`Feats (${selectedFeats.length})`}
        isOpen={openSections.feats}
        onToggle={() => toggleSection('feats')}
      >
        <FeatsSection
          selectedFeats={selectedFeatsParsed}
          filteredFeats={filteredFeatsWithChecks}
          search={featSearch}
          onSearchChange={setFeatSearch}
          onAddFeat={addFeat}
          onRemoveFeat={removeFeat}
        />
      </Accordion>

      <Accordion
        title={`${spellSectionLabel} (${selectedSpells.length})`}
        isOpen={openSections.spells}
        onToggle={() => toggleSection('spells')}
      >
        <SpellsSection
          currentClass={currentClass}
          classDef={classDef}
          classCasts={classCasts}
          castingUnlocked={castingUnlocked}
          castingStyle={castingStyle === 'none' ? null : castingStyle}
          classStartLevel={classStartLevel}
          currentLevel={currentLevel}
          currentMaxSpellLevel={currentMaxSpellLevel}
          spellSlots={spellSlots}
          selectedSpells={selectedSpellEligibilities}
          filteredSpells={filteredSpellsWithChecks}
          search={spellSearch}
          onSearchChange={setSpellSearch}
          onAddSpell={addSpell}
          onRemoveSpell={removeSpell}
        />
      </Accordion>

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

export default SkillsColumn;
