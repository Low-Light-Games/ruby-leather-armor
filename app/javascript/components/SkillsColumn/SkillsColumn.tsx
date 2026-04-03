import { useState, useMemo } from 'react';
import { useSheetsContext } from '../../contexts/SheetsContext';
import { getRaceById } from '../../rules/pathfinder_races';
import { getClassById } from '../../rules/pathfinder_classes';
import { Accordion } from '../ui/Accordion';
import { useCombatStats } from './hooks/useCombatStats';
import { useFeats } from './hooks/useFeats';
import { useSpells } from './hooks/useSpells';
import { useSkills } from './hooks/useSkills';
import { useSkillRanks } from './hooks/useSkillRanks';
import { useEquipment } from './hooks/useEquipment';
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
    skillRanks, setSkillRanks,
    markSheetDirty,
  } = useSheetsContext();

  const [openSections, setOpenSections] = useState<Record<string, boolean>>({
    skills: false,
    equipment: false,
    feats: false,
    spells: false,
  });

  const toggleSection = (section: string) => {
    setOpenSections(prev => ({ ...prev, [section]: !prev[section] }));
  };

  // ── Resolve race & class definitions ───────────────────────────

  const race = useMemo(() => currentRace ? getRaceById(currentRace) : undefined, [currentRace]);
  const classDef = useMemo(() => currentClass ? getClassById(currentClass) : undefined, [currentClass]);

  // ── Hooks ──────────────────────────────────────────────────────

  const { combatStats, combatStatCalculations, totalACP, equipSkillBonuses } = useCombatStats({
    finalAttributes, race, classDef, currentLevel,
    selectedFeats, selectedItems, currentCurrency,
  });

  const feats = useFeats({
    selectedFeats,
    setSelectedFeats,
    finalAttributes,
    currentRace,
    currentClass,
    classDef,
    currentLevel,
    onSheetDirty: markSheetDirty,
  });

  const spells = useSpells({
    selectedSpells, setSelectedSpells,
    currentClass, classDef, currentLevel,
    intelligenceScore: finalAttributes.intelligence,
    onSheetDirty: markSheetDirty,
  });

  const skillRankUi = useSkillRanks({
    skillRanks,
    setSkillRanks,
    currentClass,
    currentLevel,
    currentRace,
    intelligenceScore: finalAttributes.intelligence,
    classDef,
    onSheetDirty: markSheetDirty,
  });

  const equipment = useEquipment({
    selectedItems,
    setSelectedItems,
    currentCurrency,
    setCurrentCurrency,
    currentClass,
    onSheetDirty: markSheetDirty,
  });

  const { calculatedSkills, racialSkillBonuses } = useSkills({
    finalAttributes, race,
    featSkillBonuses: feats.featSkillBonuses,
    equipSkillBonuses,
    totalACP,
    skillRanks,
    classId: currentClass,
    level: currentLevel,
  });

  // ── Render ─────────────────────────────────────────────────────

  return (
    <div className="skills-column">
      <div className="combat-stats-panel">
        <div className="combat-stats-panel-header">Combat Stats</div>
        <div className="combat-stats-panel-body">
          <CombatStatsSection
            combatStats={combatStats}
            combatStatCalculations={combatStatCalculations}
          />
        </div>
      </div>

      <Accordion
        title="Skills"
        isOpen={openSections.skills}
        onToggle={() => toggleSection('skills')}
      >
        <SkillsSection
          skills={calculatedSkills}
          racialBonuses={racialSkillBonuses}
          featBonuses={feats.featSkillBonuses}
          canAssignRanks={skillRankUi.canAssignRanks}
          pointsSummary={skillRankUi.pointsSummary}
          onAdjustRank={skillRankUi.adjustRank}
        />
      </Accordion>

      <Accordion
        title={`Equipment (${selectedItems.length})`}
        isOpen={openSections.equipment}
        onToggle={() => toggleSection('equipment')}
      >
        <EquipmentSection
          currentClass={currentClass}
          {...equipment}
          encumbrance={{
            totalWeight: combatStats.totalWeight,
            encumbranceTier: combatStats.encumbranceTier,
            carryCapacity: combatStats.carryCapacity,
          }}
          encumbranceCalculation={combatStatCalculations.encumbrance}
        />
      </Accordion>

      <Accordion
        title={`Feats (${selectedFeats.length})`}
        isOpen={openSections.feats}
        onToggle={() => toggleSection('feats')}
      >
        <FeatsSection
          featPoolBlocks={feats.featPoolBlocks}
          search={feats.featSearch}
          onSearchChange={feats.setFeatSearch}
          onAddFeat={feats.addFeatToPool}
          onRemoveFeat={feats.removeFeat}
        />
      </Accordion>

      <Accordion
        title={`${spells.spellSectionLabel} (${selectedSpells.length})`}
        isOpen={openSections.spells}
        onToggle={() => toggleSection('spells')}
      >
        <SpellsSection
          currentClass={currentClass}
          classDef={classDef}
          classCasts={spells.classCasts}
          castingUnlocked={spells.castingUnlocked}
          castingStyle={spells.castingStyle}
          classStartLevel={spells.classStartLevel}
          currentLevel={currentLevel}
          currentMaxSpellLevel={spells.currentMaxSpellLevel}
          spellSlots={spells.spellSlots}
          selectedSpells={spells.selectedSpellEligibilities}
          filteredSpells={spells.filteredSpellsWithChecks}
          search={spells.spellSearch}
          onSearchChange={spells.setSpellSearch}
          onAddSpell={spells.addSpell}
          onRemoveSpell={spells.removeSpell}
        />
      </Accordion>

      {feats.featChoiceModal && (
        <FeatChoiceModal
          feat={feats.featChoiceModal.feat}
          choiceType={feats.featChoiceModal.choiceType}
          search={feats.featChoiceSearch}
          onSearchChange={feats.setFeatChoiceSearch}
          onConfirm={feats.confirmFeatChoice}
          onCancel={feats.cancelFeatChoice}
          alreadySelected={feats.rawFeatEntries}
        />
      )}
    </div>
  );
};

export default SkillsColumn;
