import React from 'react';
import { Accordion } from '../ui/Accordion';
import type { ClassDefinition } from '../../rules/pathfinder_classes';
import type { CombatStats } from './hooks/useCombatStats';
import type { CombatStatCalculations } from './combatHelp/combatCalcTypes';
import type { CalculatedSkill } from './hooks/useSkills';
import type { UseEquipmentResult } from './hooks/useEquipment';
import type { FeatPoolBlockUi, FeatChoiceModalState } from './hooks/useFeats';
import type { UseSpellsResult } from './hooks/useSpells';
import type { SkillPointsSummary } from './hooks/useSkillRanks';
import type { FeatPoolId } from '../../rules/pathfinder_feat_pools';
import { SkillsSection } from './sections/SkillsSection';
import { EquipmentSection } from './sections/EquipmentSection';
import { FeatsSection } from './sections/FeatsSection';
import { SpellsSection } from './sections/SpellsSection';
import FeatChoiceModal from './FeatChoiceModal';

export interface SkillsColumnSectionsProps {
  openSections: Record<string, boolean>;
  onToggleSection: (section: string) => void;
  currentClass: string | null;
  classDef: ClassDefinition | undefined;
  currentLevel: number;
  selectedFeats: string[];
  selectedSpells: string[];
  selectedItemCount: number;
  calculatedSkills: CalculatedSkill[];
  racialSkillBonuses: Record<string, number>;
  featSkillBonuses: Record<string, number>;
  equipment: UseEquipmentResult;
  combatStats: CombatStats;
  combatStatCalculations: CombatStatCalculations;
  featPoolBlocks: FeatPoolBlockUi[];
  featSearch: string;
  setFeatSearch: (v: string) => void;
  addFeatToPool: (poolId: FeatPoolId, featId: string) => void;
  onRemoveFeat: (encoded: string) => void;
  spells: UseSpellsResult;
  featChoiceModal: FeatChoiceModalState | null;
  featChoiceSearch: string;
  setFeatChoiceSearch: (v: string) => void;
  confirmFeatChoice: (choice: string) => void;
  cancelFeatChoice: () => void;
  rawFeatEntries: string[];
  canAssignRanks: boolean;
  pointsSummary: SkillPointsSummary | null;
  onAdjustRank: (skillName: string, delta: 1 | -1) => void;
}

export const SkillsColumnSections: React.FC<SkillsColumnSectionsProps> = ({
  openSections,
  onToggleSection,
  currentClass,
  classDef,
  currentLevel,
  selectedFeats,
  selectedSpells,
  selectedItemCount,
  calculatedSkills,
  racialSkillBonuses,
  featSkillBonuses,
  equipment,
  combatStats,
  combatStatCalculations,
  featPoolBlocks,
  featSearch,
  setFeatSearch,
  addFeatToPool,
  onRemoveFeat,
  spells,
  featChoiceModal,
  featChoiceSearch,
  setFeatChoiceSearch,
  confirmFeatChoice,
  cancelFeatChoice,
  rawFeatEntries,
  canAssignRanks,
  pointsSummary,
  onAdjustRank,
}) => (
  <>
    <Accordion
      title={currentClass ? 'Skills' : 'Skills (select a class to assign ranks)'}
      isOpen={openSections.skills}
      onToggle={() => onToggleSection('skills')}
    >
      <SkillsSection
        skills={calculatedSkills}
        racialBonuses={racialSkillBonuses}
        featBonuses={featSkillBonuses}
        canAssignRanks={canAssignRanks}
        pointsSummary={pointsSummary}
        onAdjustRank={onAdjustRank}
        selectedClassName={classDef?.name ?? null}
      />
    </Accordion>

    <Accordion
      title={`Equipment (${selectedItemCount})`}
      isOpen={openSections.equipment}
      onToggle={() => onToggleSection('equipment')}
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
      onToggle={() => onToggleSection('feats')}
    >
      <FeatsSection
        featPoolBlocks={featPoolBlocks}
        search={featSearch}
        onSearchChange={setFeatSearch}
        onAddFeat={addFeatToPool}
        onRemoveFeat={onRemoveFeat}
      />
    </Accordion>

    <Accordion
      title={`${spells.spellSectionLabel} (${selectedSpells.length})`}
      isOpen={openSections.spells}
      onToggle={() => onToggleSection('spells')}
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

    {featChoiceModal && (
      <FeatChoiceModal
        feat={featChoiceModal.feat}
        choiceType={featChoiceModal.choiceType}
        search={featChoiceSearch}
        onSearchChange={setFeatChoiceSearch}
        onConfirm={confirmFeatChoice}
        onCancel={cancelFeatChoice}
        alreadySelected={rawFeatEntries}
      />
    )}
  </>
);
