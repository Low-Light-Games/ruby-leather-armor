import React from 'react'
import { Accordion } from '../../ui/Accordion'
import type { DerivedStats } from '../../../types'
import type { ItemDefinition } from '../../../rules/pathfinder_items_types'
import type { FeatDefinition } from '../../../rules/pathfinder_feats_types'
import { formatMod } from '../../../utils/formatting'
import { getWeaponAttackMod } from '../../../rules/damage'

export interface WeaponsAccordionProps {
  isOpen: boolean
  onToggle: () => void
  equippedWeapons: { item: ItemDefinition; id: string }[]
  ds: DerivedStats
  featDefs: FeatDefinition[]
  rollWeaponDamage: (itemId: string) => void
}

const WeaponsAccordion: React.FC<WeaponsAccordionProps> = ({
  isOpen,
  onToggle,
  equippedWeapons,
  ds,
  featDefs,
  rollWeaponDamage,
}) => (
  <Accordion title={`Weapons (${equippedWeapons.length})`} isOpen={isOpen} onToggle={onToggle}>
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
)

export default WeaponsAccordion
