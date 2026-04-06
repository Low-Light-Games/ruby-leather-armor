import { useState, useMemo } from 'react';
import { useSheetsContext } from '../../contexts/SheetsContext';
import { getRaceById } from '../../rules/pathfinder_races';
import { getClassById } from '../../rules/pathfinder_classes';
import { useCombatStats } from './hooks/useCombatStats';
import { useFeats } from './hooks/useFeats';
import { useSpells } from './hooks/useSpells';
import { useSkills } from './hooks/useSkills';
import { useSkillRanks } from './hooks/useSkillRanks';
import { useEquipment } from './hooks/useEquipment';
import { CombatStatsPanel } from './CombatStatsPanel';
import { SkillsColumnSections } from './SkillsColumnSections';
import './SkillsColumn.scss';

export const SkillsColumn = () => {
  const {
    finalAttributes,
    currentRace,
    currentClass,
    currentLevel,
    selectedFeats,
    setSelectedFeats,
    selectedSpells,
    setSelectedSpells,
    selectedItems,
    setSelectedItems,
    currentCurrency,
    setCurrentCurrency,
    skillRanks,
    setSkillRanks,
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

  const race = useMemo(() => (currentRace ? getRaceById(currentRace) : undefined), [currentRace]);
  const classDef = useMemo(
    () => (currentClass ? getClassById(currentClass) : undefined),
    [currentClass],
  );

  const { combatStats, combatStatCalculations, totalACP, equipSkillBonuses } = useCombatStats({
    finalAttributes,
    race,
    classDef,
    currentLevel,
    selectedFeats,
    selectedItems,
    currentCurrency,
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
    selectedSpells,
    setSelectedSpells,
    currentClass,
    classDef,
    currentLevel,
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
    finalAttributes,
    race,
    featSkillBonuses: feats.featSkillBonuses,
    equipSkillBonuses,
    totalACP,
    skillRanks,
    classId: currentClass,
    level: currentLevel,
  });

  return (
    <div className="skills-column">
      <CombatStatsPanel combatStats={combatStats} combatStatCalculations={combatStatCalculations} />

      <SkillsColumnSections
        openSections={openSections}
        onToggleSection={toggleSection}
        currentClass={currentClass}
        classDef={classDef}
        currentLevel={currentLevel}
        selectedFeats={selectedFeats}
        selectedSpells={selectedSpells}
        selectedItemCount={selectedItems.length}
        calculatedSkills={calculatedSkills}
        racialSkillBonuses={racialSkillBonuses}
        featSkillBonuses={feats.featSkillBonuses}
        equipment={equipment}
        combatStats={combatStats}
        combatStatCalculations={combatStatCalculations}
        featPoolBlocks={feats.featPoolBlocks}
        featSearch={feats.featSearch}
        setFeatSearch={feats.setFeatSearch}
        addFeatToPool={feats.addFeatToPool}
        onRemoveFeat={feats.removeFeat}
        spells={spells}
        featChoiceModal={feats.featChoiceModal}
        featChoiceSearch={feats.featChoiceSearch}
        setFeatChoiceSearch={feats.setFeatChoiceSearch}
        confirmFeatChoice={feats.confirmFeatChoice}
        cancelFeatChoice={feats.cancelFeatChoice}
        rawFeatEntries={feats.rawFeatEntries}
        canAssignRanks={skillRankUi.canAssignRanks}
        pointsSummary={skillRankUi.pointsSummary}
        onAdjustRank={skillRankUi.adjustRank}
      />
    </div>
  );
};

export default SkillsColumn;
