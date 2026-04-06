import React, { useState, useMemo, useCallback, useEffect } from 'react'
import type { AdventureSheet, AttributeType, DerivedStats } from '../../types'
import type { ItemDefinition } from '../../rules/pathfinder_items_types'
import type { SpellDefinition } from '../../rules/pathfinder_spells_types'
import type { SpellbookSearchResult } from './hooks/useSpellbook'
import type { SkillRanksMap } from '../../rules/pathfinder_skill_ranks'
import { getItemById } from '../../rules/pathfinder_items'
import { getFeatById } from '../../rules/pathfinder_feats'
import { getClassById } from '../../rules/pathfinder_classes'
import { abilityModifier } from '../../rules/pathfinder_skills'
import {
  normalizeSkillRanksMap,
  tryAdjustSkillRank,
  spentSkillPoints,
  totalSkillPoints,
} from '../../rules/pathfinder_skill_ranks'
import CombatStatsGrid from './CharacterSidebar/CombatStatsGrid'
import ConditionsBadges from './CharacterSidebar/ConditionsBadges'
import SpellsSection from './CharacterSidebar/SpellsSection'
import CharacterActions from './CharacterSidebar/CharacterActions'
import AttributesAccordion from './CharacterSidebar/AttributesAccordion'
import SkillsAccordion from './CharacterSidebar/SkillsAccordion'
import WeaponsAccordion from './CharacterSidebar/WeaponsAccordion'
import InventoryAccordion from './CharacterSidebar/InventoryAccordion'
import FeatsAccordion from './CharacterSidebar/FeatsAccordion'

interface CharacterSidebarProps {
  sheet: AdventureSheet
  ds: DerivedStats
  rollFort: () => void
  rollRef: () => void
  rollWill: () => void
  rollMeleeAttack: () => void
  rollRangedAttack: () => void
  rollInitiative: () => void
  rollAbility: (attr: AttributeType) => void
  rollSkill: (skillName: string, total: number) => void
  rollWeaponDamage: (itemId: string) => void
  rollSpellDamage: (spellId: string) => void
  rollUnarmedDamage: () => void
  rollConcentration: () => void
  concentrationMod: number | null
  spellbookSearch: string
  setSpellbookSearch: (v: string) => void
  spellbookSaving: boolean
  spellbookSearchResults: SpellbookSearchResult[]
  addSpellToSpellbook: (spell: SpellDefinition) => void
  toggleEquip: (itemId: string) => void
  equipSaving: boolean
  equipError: string | null
  patchSkillRanks: (next: SkillRanksMap) => Promise<void>
  rankSaving: boolean
  rankErrors: string[]
  dismissRankErrors: () => void
}

export const CharacterSidebar: React.FC<CharacterSidebarProps> = ({
  sheet, ds,
  rollFort, rollRef, rollWill,
  rollMeleeAttack, rollRangedAttack, rollInitiative,
  rollAbility, rollSkill, rollWeaponDamage, rollSpellDamage,
  rollUnarmedDamage, rollConcentration, concentrationMod,
  spellbookSearch, setSpellbookSearch, spellbookSaving,
  spellbookSearchResults, addSpellToSpellbook,
  toggleEquip, equipSaving, equipError,
  patchSkillRanks, rankSaving, rankErrors, dismissRankErrors,
}) => {
  const [openSections, setOpenSections] = useState<Record<string, boolean>>({
    attributes: true, weapons: false, inventory: false,
    skills: false, feats: false, spells: false,
  })
  const toggleSection = (section: string) =>
    setOpenSections(prev => ({ ...prev, [section]: !prev[section] }))

  useEffect(() => {
    if (rankErrors.length > 0) {
      setOpenSections(prev => (prev.skills ? prev : { ...prev, skills: true }))
    }
  }, [rankErrors])

  const feats = sheet.details?.feats || []
  const featDefs = useMemo(
    () =>
      feats.map(entry => getFeatById(entry)).filter((f): f is NonNullable<typeof f> => !!f),
    [feats],
  )

  const classDef = useMemo(
    () => (sheet.character_class ? getClassById(sheet.character_class) : undefined),
    [sheet.character_class],
  )

  const ranksMap = useMemo(() => normalizeSkillRanksMap(sheet.skill_ranks), [sheet.skill_ranks])

  const pointsSummary = useMemo(() => {
    if (!sheet.character_class || !classDef) return null
    const intMod = abilityModifier(ds.final_scores.intelligence)
    const total = totalSkillPoints(sheet.level, intMod, classDef.skillPointsBase, sheet.race)
    const spent = spentSkillPoints(ranksMap, sheet.character_class)
    return { spent, total, remaining: Math.max(0, total - spent) }
  }, [sheet.character_class, classDef, sheet.level, ds.final_scores.intelligence, sheet.race, ranksMap])

  const handleRankDelta = useCallback(
    async (skillName: string, delta: 1 | -1) => {
      if (!sheet.character_class || !classDef) return
      const intMod = abilityModifier(ds.final_scores.intelligence)
      const next = tryAdjustSkillRank(ranksMap, skillName, delta, {
        classId: sheet.character_class,
        level: sheet.level,
        intMod,
        skillPointsBase: classDef.skillPointsBase,
        raceId: sheet.race,
      })
      if (next) await patchSkillRanks(next)
    },
    [classDef, ds.final_scores.intelligence, patchSkillRanks, ranksMap, sheet.character_class, sheet.level, sheet.race],
  )

  const equippedWeapons: { item: ItemDefinition; id: string }[] = useMemo(() => {
    const items = sheet.details?.items ?? []
    const result: { item: ItemDefinition; id: string }[] = []
    for (const owned of items) {
      if (!owned.equipped) continue
      const def = getItemById(owned.itemId) ?? owned.definition
      if (!def || !def.damageDice) continue
      if (def.itemType === 'weapon' || def.itemType === 'shield') {
        result.push({ item: def, id: owned.itemId })
      }
    }
    return result
  }, [sheet.details?.items])

  const allItems: { item: ItemDefinition; id: string; quantity: number; equipped: boolean }[] = useMemo(() => {
    const items = sheet.details?.items ?? []
    const result: { item: ItemDefinition; id: string; quantity: number; equipped: boolean }[] = []
    for (const owned of items) {
      const def = getItemById(owned.itemId) ?? owned.definition
      if (!def) continue
      result.push({ item: def, id: owned.itemId, quantity: owned.quantity, equipped: owned.equipped })
    }
    return result
  }, [sheet.details?.items])

  return (
    <div className="adventure-column character-column">
      <h2>{sheet.name}</h2>
      {(sheet.race || sheet.character_class) && (
        <p className="char-subtitle">
          {[sheet.race, sheet.character_class].filter(Boolean).join(' ')}
          {sheet.level > 1 && ` (Lv ${sheet.level})`}
        </p>
      )}

      {ds.active_conditions?.length > 0 && (
        <ConditionsBadges
          conditions={ds.active_conditions}
          restrictions={ds.condition_restrictions ?? []}
        />
      )}

      <CombatStatsGrid
        sheet={sheet} ds={ds}
        equippedWeapons={equippedWeapons}
        rollFort={rollFort} rollRef={rollRef} rollWill={rollWill}
        rollWeaponDamage={rollWeaponDamage}
        rollUnarmedDamage={rollUnarmedDamage}
      />

      <div className="collapsible-sections">
        <AttributesAccordion
          isOpen={openSections.attributes}
          onToggle={() => toggleSection('attributes')}
          sheet={sheet}
          ds={ds}
          rollAbility={rollAbility}
        />
        <SkillsAccordion
          isOpen={openSections.skills}
          onToggle={() => toggleSection('skills')}
          sheet={sheet}
          ds={ds}
          classDef={classDef}
          ranksMap={ranksMap}
          pointsSummary={pointsSummary}
          handleRankDelta={handleRankDelta}
          rankSaving={rankSaving}
          rankErrors={rankErrors}
          dismissRankErrors={dismissRankErrors}
          rollSkill={rollSkill}
        />
        <WeaponsAccordion
          isOpen={openSections.weapons}
          onToggle={() => toggleSection('weapons')}
          equippedWeapons={equippedWeapons}
          ds={ds}
          featDefs={featDefs}
          rollWeaponDamage={rollWeaponDamage}
        />
        <InventoryAccordion
          isOpen={openSections.inventory}
          onToggle={() => toggleSection('inventory')}
          allItems={allItems}
          equipError={equipError}
          toggleEquip={toggleEquip}
          equipSaving={equipSaving}
        />
        <FeatsAccordion
          isOpen={openSections.feats}
          onToggle={() => toggleSection('feats')}
          feats={feats}
        />
        <SpellsSection
          sheet={sheet}
          isOpen={openSections.spells}
          onToggle={() => toggleSection('spells')}
          rollSpellDamage={rollSpellDamage}
          spellbookSearch={spellbookSearch}
          setSpellbookSearch={setSpellbookSearch}
          spellbookSaving={spellbookSaving}
          spellbookSearchResults={spellbookSearchResults}
          addSpellToSpellbook={addSpellToSpellbook}
        />
      </div>

      <CharacterActions
        rollMeleeAttack={rollMeleeAttack}
        rollRangedAttack={rollRangedAttack}
        rollInitiative={rollInitiative}
        rollConcentration={rollConcentration}
        concentrationMod={concentrationMod}
      />
    </div>
  )
}
