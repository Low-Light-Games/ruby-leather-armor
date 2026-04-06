import React from 'react'
import { Accordion } from '../../ui/Accordion'
import type { AdventureSheet, AttributeType, DerivedStats } from '../../../types'
import { formatMod, ABILITY_ABBR, ATTRIBUTE_ORDER } from '../../../utils/formatting'

export interface AttributesAccordionProps {
  isOpen: boolean
  onToggle: () => void
  sheet: AdventureSheet
  ds: DerivedStats
  rollAbility: (attr: AttributeType) => void
}

const AttributesAccordion: React.FC<AttributesAccordionProps> = ({
  isOpen,
  onToggle,
  sheet,
  ds,
  rollAbility,
}) => (
  <Accordion title="Attributes" isOpen={isOpen} onToggle={onToggle}>
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
)

export default AttributesAccordion
