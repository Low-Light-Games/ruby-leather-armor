import React from 'react'
import { Accordion } from '../../ui/Accordion'
import { getFeatById, featDisplayName } from '../../../rules/pathfinder_feats'

export interface FeatsAccordionProps {
  isOpen: boolean
  onToggle: () => void
  feats: string[]
}

const FeatsAccordion: React.FC<FeatsAccordionProps> = ({ isOpen, onToggle, feats }) => (
  <Accordion title={`Feats (${feats.length})`} isOpen={isOpen} onToggle={onToggle}>
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
)

export default FeatsAccordion
