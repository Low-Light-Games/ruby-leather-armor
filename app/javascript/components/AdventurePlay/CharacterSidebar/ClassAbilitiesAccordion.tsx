import React from 'react'
import { Accordion } from '../../ui/Accordion'

export interface ClassAbilityEntry {
  id: string
  name: string
  summary: string | null
}

export interface ClassAbilitiesAccordionProps {
  isOpen: boolean
  onToggle: () => void
  classAbilities: ClassAbilityEntry[]
}

const ClassAbilitiesAccordion: React.FC<ClassAbilitiesAccordionProps> = ({
  isOpen,
  onToggle,
  classAbilities,
}) => (
  <Accordion
    title={`Class abilities (${classAbilities.length})`}
    isOpen={isOpen}
    onToggle={onToggle}
  >
    <div className="feats-spells-list">
      {classAbilities.length === 0 ? (
        <p className="empty-hint">No class abilities for this class and level.</p>
      ) : (
        classAbilities.map(entry => (
          <div key={entry.id} className="fs-item" title={entry.summary ?? undefined}>
            <span className="fs-name">{entry.name}</span>
          </div>
        ))
      )}
    </div>
  </Accordion>
)

export default ClassAbilitiesAccordion
