import React, { useState, useMemo } from 'react'
import { Accordion } from '../ui/Accordion'
import type { AdventureSheet, AttributeType, DerivedStats } from '../../types'
import type { ItemDefinition } from '../../rules/pathfinder_items_types'
import type { SpellDefinition } from '../../rules/pathfinder_spells_types'
import type { SpellbookSearchResult } from './hooks/useSpellbook'
import { formatMod, ABILITY_ABBR, ATTRIBUTE_ORDER } from '../../utils/formatting'
import { getItemById } from '../../rules/pathfinder_items'
import { getFeatById, featDisplayName } from '../../rules/pathfinder_feats'
import { getCastingStyle } from '../../rules/pathfinder_spells'
import { getWeaponAttackMod } from '../../rules/damage'
import CombatStatsGrid from './CharacterSidebar/CombatStatsGrid'
import ConditionsBadges from './CharacterSidebar/ConditionsBadges'
import SpellsSection from './CharacterSidebar/SpellsSection'
import CharacterActions from './CharacterSidebar/CharacterActions'

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
}) => {
  const [openSections, setOpenSections] = useState<Record<string, boolean>>({
    attributes: true, weapons: false, inventory: false,
    skills: false, feats: false, spells: false,
  })
  const toggleSection = (section: string) =>
    setOpenSections(prev => ({ ...prev, [section]: !prev[section] }))

  const feats = sheet.details?.feats || []
  const featDefs = useMemo(() =>
    feats.map(id => getFeatById(id)).filter((f): f is NonNullable<typeof f> => !!f),
    [feats]
  )

  const equippedWeapons: { item: ItemDefinition; id: string }[] = useMemo(() => {
    const items = sheet.details?.items ?? []
    const result: { item: ItemDefinition; id: string }[] = []
    for (const owned of items) {
      if (!owned.equipped) continue
      const def = getItemById(owned.itemId)
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
      const def = getItemById(owned.itemId)
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
        <Accordion title="Attributes" isOpen={openSections.attributes} onToggle={() => toggleSection('attributes')}>
          <div className="attributes-list">
            {ATTRIBUTE_ORDER.map(attr => {
              const base = sheet[attr]
              const final = ds.final_scores[attr] ?? base
              const racial = final - base
              const mod = ds.mods[attr] ?? 0
              return (
                <div key={attr} className="attribute-item">
                  <span className="attr-label">{ABILITY_ABBR[attr]}</span>
                  <span className="attr-score">
                    {base}
                    {racial !== 0 && (
                      <span className={`racial ${racial > 0 ? 'pos' : 'neg'}`}>
                        {racial > 0 ? '+' : ''}{racial}
                      </span>
                    )}
                    {' = '}
                    <strong>{final}</strong>
                  </span>
                  <span className="attr-mod">{formatMod(mod)}</span>
                  <button className="roll-dice-btn" onClick={() => rollAbility(attr)}
                    title={`Roll ${ABILITY_ABBR[attr]} Check`} aria-label={`Roll ${ABILITY_ABBR[attr]} Check`}>
                    🎲
                  </button>
                </div>
              )
            })}
          </div>
        </Accordion>

        <Accordion title="Skills" isOpen={openSections.skills} onToggle={() => toggleSection('skills')}>
          <div className="skills-list-adventure">
            {ds.skills.map(skill => (
              <div key={skill.name} className={`skill-row ${skill.trained_only ? 'trained-only' : ''}`}>
                <span className="skill-name">
                  {skill.name}
                  {skill.trained_only && <span className="badge-t">T</span>}
                </span>
                <span className={`skill-mod ${skill.total >= 0 ? 'positive' : 'negative'}`}>
                  {formatMod(skill.total)}
                </span>
                <button className="roll-dice-btn" onClick={() => rollSkill(skill.name, skill.total)}
                  title={`Roll ${skill.name} Check`} aria-label={`Roll ${skill.name} Check`}>
                  🎲
                </button>
              </div>
            ))}
          </div>
        </Accordion>

        <Accordion title={`Weapons (${equippedWeapons.length})`} isOpen={openSections.weapons} onToggle={() => toggleSection('weapons')}>
          <div className="weapons-list">
            {equippedWeapons.length === 0 ? (
              <p className="empty-hint">No weapons equipped.</p>
            ) : (
              equippedWeapons.map(({ item, id }) => {
                const atkMod = getWeaponAttackMod(item, ds, featDefs)
                const isBash = item.itemType === 'shield'
                return (
                  <div key={id} className="weapon-row" title={item.summary ?? undefined}>
                    <div className="weapon-info">
                      <span className="weapon-name">{item.name}{isBash ? ' (bash)' : ''}</span>
                      <span className="weapon-stats">
                        {item.damageDice} {item.damageType}{' | '}Atk {formatMod(atkMod.total)}
                      </span>
                    </div>
                    <button className="roll-dice-btn" onClick={() => rollWeaponDamage(id)}
                      title={`Roll ${item.name} Damage`} aria-label={`Roll ${item.name} Damage`}>
                      🎲
                    </button>
                  </div>
                )
              })
            )}
          </div>
        </Accordion>

        <Accordion title={`Inventory (${allItems.length})`} isOpen={openSections.inventory} onToggle={() => toggleSection('inventory')}>
          <div className="inventory-list">
            {equipError && <p className="equip-error">{equipError}</p>}
            {allItems.length === 0 ? (
              <p className="empty-hint">No items.</p>
            ) : (
              allItems.map(({ item, id, quantity, equipped }) => (
                <div key={id} className={`inventory-row ${equipped ? 'is-equipped' : ''}`} title={item.summary ?? undefined}>
                  <span className="inventory-name">
                    {item.name}
                    {quantity > 1 && <span className="inventory-qty"> x{quantity}</span>}
                  </span>
                  <span className="inventory-meta">
                    <span className={`inventory-type type-${item.itemType}`}>{item.itemType}</span>
                    <button className={`equip-toggle ${equipped ? 'equipped' : 'unequipped'}`}
                      onClick={() => toggleEquip(id)} disabled={equipSaving}
                      title={equipped ? 'Unequip' : 'Equip'}>
                      {equipped ? 'Unequip' : 'Equip'}
                    </button>
                  </span>
                </div>
              ))
            )}
          </div>
        </Accordion>

        <Accordion title={`Feats (${feats.length})`} isOpen={openSections.feats} onToggle={() => toggleSection('feats')}>
          <div className="feats-spells-list">
            {feats.length === 0 ? (
              <p className="empty-hint">No feats selected.</p>
            ) : (
              feats.map(entry => {
                const feat = getFeatById(entry)
                if (!feat) return null
                const displayName = featDisplayName(entry)
                return (
                  <div key={entry} className="fs-item" title={feat.summary}>
                    <span className="fs-name">{displayName}</span>
                    <span className={`fs-tag cat-${feat.category}`}>{feat.category}</span>
                  </div>
                )
              })
            )}
          </div>
        </Accordion>

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
