import { useState, useEffect, useRef, useCallback } from 'react'
import type { AdventureMessage, DerivedStats, AdventureSheet } from '../../types'
import RollResultModal, { RollResultDisplay } from '../RollResultModal'
import { useAuth } from '../../contexts/AuthContext'
import { useAdventureMessages } from './hooks/useAdventureMessages'
import { ResolutionMethod } from './rollHelpers'
import ChatMessage from './ChatMessage'
import MechanicsGroup, { isMechanicalMessage } from './MechanicsGroup'
import PendingRollsPanel from './PendingRollsPanel'
import PendingInitiativePanel from './PendingInitiativePanel'
import './AdventureChat.scss'

type MessageGroup =
  | { type: 'single'; msg: AdventureMessage }
  | { type: 'group'; messages: AdventureMessage[] }

function groupMessages(messages: AdventureMessage[]): MessageGroup[] {
  const result: MessageGroup[] = []
  let i = 0
  while (i < messages.length) {
    if (isMechanicalMessage(messages[i])) {
      const group: AdventureMessage[] = []
      while (i < messages.length && isMechanicalMessage(messages[i])) {
        group.push(messages[i])
        i++
      }
      result.push({ type: 'group', messages: group })
    } else {
      result.push({ type: 'single', msg: messages[i] })
      i++
    }
  }
  return result
}

interface AdventureChatProps {
  adventureId: number
  derivedStats?: DerivedStats | null
  adventureSheet?: AdventureSheet | null
  adventureEnded?: boolean
  endReason?: 'player_death' | 'adventure_complete' | null
  onAdventureComplete?: () => void
  onDmResponse?: () => void
  onSheetUpdate?: () => void
}

export const AdventureChat = ({
  adventureId,
  derivedStats,
  adventureSheet,
  adventureEnded = false,
  endReason = null,
  onAdventureComplete,
  onDmResponse,
  onSheetUpdate,
}: AdventureChatProps) => {
  const { user } = useAuth()
  const [input, setInput] = useState('')
  const [askDm, setAskDm] = useState(false)
  const [rollModalDisplay, setRollModalDisplay] = useState<RollResultDisplay | null>(null)
  const [rollModalTargetIdx, setRollModalTargetIdx] = useState<number | null>(null)
  const messagesEndRef = useRef<HTMLDivElement>(null)

  const {
    messages, sending, loadingHistory,
    pendingRolls, setPendingRolls,
    pendingInitiative,
    sendMessage, sendRolls, sendInitiative, handleRetry,
  } = useAdventureMessages({ adventureId, derivedStats, onAdventureComplete, onDmResponse, onSheetUpdate })

  const scrollToBottom = useCallback(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [])

  useEffect(() => { scrollToBottom() }, [messages, scrollToBottom])

  const handleSend = () => {
    const text = input.trim()
    if (!text || sending || adventureEnded) return
    const mode = askDm ? 'dm_query' : undefined
    setInput('')
    setAskDm(false)
    sendMessage(text, mode)
  }

  const setRollValue = (index: number, value: number, method: ResolutionMethod = 'manual') => {
    if (!pendingRolls) return
    const updated = [...pendingRolls.entries]
    updated[index] = { ...updated[index], value, resolution_method: method }
    setPendingRolls({ ...pendingRolls, entries: updated })
  }

  const handleRollModal = (index: number, display: RollResultDisplay) => {
    setRollModalTargetIdx(index)
    setRollModalDisplay(display)
  }

  const handleRollModalClose = () => {
    if (rollModalDisplay && rollModalTargetIdx != null) {
      setRollValue(rollModalTargetIdx, rollModalDisplay.result.total, 'roll')
    }
    setRollModalDisplay(null)
    setRollModalTargetIdx(null)
  }

  const allRollsFilled = pendingRolls?.entries.every(e => e.value != null) ?? false

  const handleRollsSubmit = () => {
    if (!pendingRolls || !allRollsFilled || adventureEnded) return

    const rolls = pendingRolls.entries.map(e => ({
      roll_value: e.value!,
      roll_description: e.request.description,
      request_id: e.request.request_id,
      resolution_method: e.resolution_method || 'manual',
    }))

    setPendingRolls(null)
    sendRolls(rolls)
  }

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      handleSend()
    }
  }

  const terminalNotice = endReason === 'player_death'
    ? 'Your character has died. This adventure has ended.'
    : 'This adventure has reached its conclusion.'

  return (
    <div className="adventure-chat">
      <h2>Game Master</h2>

      <div className="chat-messages">
        {loadingHistory ? (
          <div className="chat-loading">Loading conversation...</div>
        ) : messages.length === 0 ? (
          <div className="chat-empty">
            <p>Your adventure awaits! Describe what your character does to begin.</p>
          </div>
        ) : (
          groupMessages(messages).map((item, i) =>
            item.type === 'group' ? (
              <MechanicsGroup key={`group-${item.messages[0].id}`} messages={item.messages} />
            ) : (
              <ChatMessage
                key={item.msg.id}
                msg={item.msg}
                isAdmin={!!user?.admin}
                onRetry={handleRetry}
              />
            )
          )
        )}
        <div ref={messagesEndRef} />
      </div>

      {pendingRolls && !sending && !adventureEnded && (
        <PendingRollsPanel
          pendingRolls={pendingRolls}
          derivedStats={derivedStats}
          onRollValueChange={setRollValue}
          onSubmit={handleRollsSubmit}
          allRollsFilled={allRollsFilled}
          onRollModal={handleRollModal}
        />
      )}

      {pendingInitiative && !sending && !adventureEnded && (
        <PendingInitiativePanel
          derivedStats={derivedStats}
          onSubmit={sendInitiative}
        />
      )}

      <RollResultModal
        roll={rollModalDisplay}
        onClose={handleRollModalClose}
      />

      {adventureEnded ? (
        <div className="chat-ended-notice" role="status" aria-live="polite">
          {terminalNotice}
        </div>
      ) : (
        <div className="chat-input-area">
          <button
            type="button"
            className={`ask-dm-toggle ${askDm ? 'active' : ''}`}
            onClick={() => setAskDm(prev => !prev)}
            disabled={sending}
            title="Toggle to ask the Game Master for help, rules clarifications, or information about the game world — without taking an action."
          >
            ❓ Ask GM
          </button>
          <div className="chat-input-wrapper">
            <textarea
              value={input}
              onChange={e => setInput(e.target.value)}
              onKeyDown={handleKeyDown}
              placeholder={askDm ? 'Ask the GM a question...' : (pendingInitiative ? 'Roll for initiative above...' : (pendingRolls ? 'Submit your rolls above, or describe another action...' : 'What does your character do?'))}
              disabled={sending}
              rows={2}
              maxLength={500}
              className={`chat-input ${askDm ? 'ask-dm-mode' : ''}`}
            />
            <span className={`char-counter ${input.length > 450 ? 'near-limit' : ''} ${input.length >= 500 ? 'at-limit' : ''}`}>
              {input.length}/500
            </span>
          </div>
          <button
            onClick={handleSend}
            disabled={sending || !input.trim()}
            className="chat-send-btn"
          >
            ➤
          </button>
        </div>
      )}
    </div>
  )
}

export default AdventureChat
