import { useState, useEffect, useRef, useCallback } from 'react'
import { AdventureMessage, RollRequest } from '../../types'
import { csrfToken } from '../../utils/api'
import './AdventureChat.scss'

interface AdventureChatProps {
  adventureId: number
  onAdventureComplete?: () => void
}

export const AdventureChat = ({ adventureId, onAdventureComplete }: AdventureChatProps) => {
  const [messages, setMessages] = useState<AdventureMessage[]>([])
  const [input, setInput] = useState('')
  const [sending, setSending] = useState(false)
  const [loadingHistory, setLoadingHistory] = useState(true)
  const [pendingRoll, setPendingRoll] = useState<RollRequest | null>(null)
  const [rollValue, setRollValue] = useState('')
  const messagesEndRef = useRef<HTMLDivElement>(null)
  const rollInputRef = useRef<HTMLInputElement>(null)

  // Auto-scroll to bottom on new messages
  const scrollToBottom = useCallback(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [])

  useEffect(() => {
    scrollToBottom()
  }, [messages, scrollToBottom])

  // Auto-focus roll input when a pending roll appears
  useEffect(() => {
    if (pendingRoll && rollInputRef.current) {
      rollInputRef.current.focus()
    }
  }, [pendingRoll])

  // Load conversation history
  useEffect(() => {
    const loadHistory = async () => {
      try {
        const res = await fetch(`/adventures/${adventureId}/messages`, {
          headers: { Accept: 'application/json' },
        })
        if (!res.ok) throw new Error('Failed to load messages')
        const data: AdventureMessage[] = await res.json()
        setMessages(data)

        // Check if the last DM message has a pending roll request
        const lastDm = [...data].reverse().find(m => m.role === 'dm')
        if (lastDm?.message_type === 'roll_request' && lastDm.metadata?.roll_request) {
          // Check if a roll_result was already submitted after it
          const lastDmIdx = data.findIndex(m => m.id === lastDm.id)
          const hasRollResult = data.slice(lastDmIdx + 1).some(m => m.message_type === 'roll_result')
          if (!hasRollResult) {
            setPendingRoll(lastDm.metadata.roll_request)
          }
        }
      } catch (err) {
        console.error('Error loading chat history:', err)
      } finally {
        setLoadingHistory(false)
      }
    }
    loadHistory()
  }, [adventureId])

  // Send a player message
  const handleSend = async () => {
    const text = input.trim()
    if (!text || sending) return

    setInput('')
    setSending(true)
    setPendingRoll(null)

    try {
      const res = await fetch(`/adventures/${adventureId}/messages`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken(),
          Accept: 'application/json',
        },
        body: JSON.stringify({ content: text }),
      })

      if (!res.ok) {
        const body = await res.json().catch(() => ({}))
        throw new Error(body.error || `HTTP ${res.status}`)
      }

      const data: { messages: AdventureMessage[] } = await res.json()
      setMessages(prev => [...prev, ...data.messages])

      // Check for roll request in the DM response
      const dmMsg = data.messages.find(m => m.role === 'dm' && m.message_type === 'roll_request')
      if (dmMsg?.metadata?.roll_request) {
        setPendingRoll(dmMsg.metadata.roll_request)
      }

      const completeMsg = data.messages.find(m => m.message_type === 'adventure_complete')
      if (completeMsg && onAdventureComplete) {
        onAdventureComplete()
      }
    } catch (err: any) {
      console.error('Error sending message:', err)
      // Show a local error message
      setMessages(prev => [
        ...prev,
        {
          id: Date.now(),
          role: 'system',
          content: `Failed to send: ${err.message}`,
          message_type: 'narrative',
          metadata: {},
          created_at: new Date().toISOString(),
        },
      ])
    } finally {
      setSending(false)
    }
  }

  // Submit a roll result
  const handleRollSubmit = async () => {
    const value = parseInt(rollValue, 10)
    if (isNaN(value) || value < 1 || !pendingRoll) return

    setSending(true)

    try {
      const res = await fetch(`/adventures/${adventureId}/messages/roll`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken(),
          Accept: 'application/json',
        },
        body: JSON.stringify({
          roll_value: value,
          roll_description: pendingRoll.description,
        }),
      })

      if (!res.ok) {
        const body = await res.json().catch(() => ({}))
        throw new Error(body.error || `HTTP ${res.status}`)
      }

      const data: { messages: AdventureMessage[] } = await res.json()
      setMessages(prev => [...prev, ...data.messages])
      setPendingRoll(null)
      setRollValue('')

      // Check if the new DM response requests another roll
      const dmMsg = data.messages.find(m => m.role === 'dm' && m.message_type === 'roll_request')
      if (dmMsg?.metadata?.roll_request) {
        setPendingRoll(dmMsg.metadata.roll_request)
      }

      const completeMsg = data.messages.find(m => m.message_type === 'adventure_complete')
      if (completeMsg && onAdventureComplete) {
        onAdventureComplete()
      }
    } catch (err: any) {
      console.error('Error submitting roll:', err)
      setMessages(prev => [
        ...prev,
        {
          id: Date.now(),
          role: 'system',
          content: `Failed to submit roll: ${err.message}`,
          message_type: 'narrative',
          metadata: {},
          created_at: new Date().toISOString(),
        },
      ])
    } finally {
      setSending(false)
    }
  }

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      handleSend()
    }
  }

  return (
    <div className="adventure-chat">
      <h2>Dungeon Master</h2>

      {/* Message list */}
      <div className="chat-messages">
        {loadingHistory ? (
          <div className="chat-loading">Loading conversation...</div>
        ) : messages.length === 0 ? (
          <div className="chat-empty">
            <p>Your adventure awaits! Describe what your character does to begin.</p>
          </div>
        ) : (
          messages.map(msg => (
            <div
              key={msg.id}
              className={`chat-message msg-${msg.role} msg-type-${msg.message_type}`}
            >
              <div className="msg-header">
                <span className="msg-role">
                  {msg.role === 'player' ? '🗡️ You' : msg.role === 'dm' ? '🐉 DM' : '📜 System'}
                </span>
              </div>
              <div className="msg-content">{msg.content}</div>
              {msg.message_type === 'roll_request' && msg.metadata?.roll_request && (
                <div className="roll-request-badge">
                  🎲 {msg.metadata.roll_request.description}
                  {msg.metadata.roll_request.dc && (
                    <span className="roll-dc"> (DC {msg.metadata.roll_request.dc})</span>
                  )}
                </div>
              )}
            </div>
          ))
        )}
        <div ref={messagesEndRef} />
      </div>

      {/* Roll submission UI */}
      {pendingRoll && !sending && (
        <div className="roll-submit-area">
          <div className="roll-prompt">
            <span className="roll-icon">🎲</span>
            <span>{pendingRoll.description}</span>
            {pendingRoll.dc && <span className="roll-dc">DC {pendingRoll.dc}</span>}
          </div>
          <div className="roll-input-row">
            <input
              ref={rollInputRef}
              type="number"
              min="1"
              max="100"
              placeholder="Enter your roll result"
              value={rollValue}
              onChange={e => setRollValue(e.target.value)}
              onKeyDown={e => {
                if (e.key === 'Enter') handleRollSubmit()
              }}
              className="roll-input"
            />
            <button
              onClick={handleRollSubmit}
              disabled={!rollValue || parseInt(rollValue, 10) < 1}
              className="roll-submit-btn"
            >
              Submit Roll
            </button>
          </div>
        </div>
      )}

      {/* Input area */}
      <div className="chat-input-area">
        <div className="chat-input-wrapper">
          <textarea
            value={input}
            onChange={e => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder={pendingRoll ? 'Submit your roll above, or describe another action...' : 'What does your character do?'}
            disabled={sending}
            rows={2}
            maxLength={500}
            className="chat-input"
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
          {sending ? (
            <span className="sending-indicator">
              <span className="dot">.</span><span className="dot">.</span><span className="dot">.</span>
            </span>
          ) : (
            '➤'
          )}
        </button>
      </div>
    </div>
  )
}

export default AdventureChat
