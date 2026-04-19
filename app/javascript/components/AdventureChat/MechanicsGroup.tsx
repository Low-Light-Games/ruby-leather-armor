import { useState } from 'react'
import type { AdventureMessage } from '../../types'

interface MechanicsGroupProps {
  messages: AdventureMessage[]
}

const MECHANICAL_TYPES = new Set<AdventureMessage['message_type']>(['combat_log', 'action_result'])

export function isMechanicalMessage(msg: AdventureMessage): boolean {
  return MECHANICAL_TYPES.has(msg.message_type)
}

const MechanicsGroup = ({ messages }: MechanicsGroupProps) => {
  const [isOpen, setIsOpen] = useState(false)
  const count = messages.length
  const label = count === 1 ? '1 action' : `${count} actions`

  return (
    <div className="mechanics-group">
      <span className="sr-only">Combat log</span>
      <button
        type="button"
        className="mechanics-group-header"
        onClick={() => setIsOpen(prev => !prev)}
        aria-expanded={isOpen}
      >
        <span className="mechanics-toggle" aria-hidden="true">{isOpen ? '▼' : '▶'}</span>
        <span className="mechanics-summary">Combat round ({label})</span>
      </button>
      {isOpen && (
        <div className="mechanics-group-body">
          {messages.map(msg => (
            <div key={msg.id} className="mechanics-line">
              {msg.content}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

export default MechanicsGroup
