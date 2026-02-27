import { useState, useEffect, useRef, useCallback } from 'react'
import { AdventureMessage, RollRequest } from '../../types'
import { csrfToken } from '../../utils/api'
import './AdventureChat.scss'

const OPTIMISTIC_ID = -1
const THINKING_ID = -2
const ERROR_ID = -3

function isSentinel(id: number) {
  return id === OPTIMISTIC_ID || id === THINKING_ID || id === ERROR_ID
}

interface AdventureChatProps {
  adventureId: number
  onAdventureComplete?: () => void
  onDmResponse?: () => void
}

export const AdventureChat = ({ adventureId, onAdventureComplete, onDmResponse }: AdventureChatProps) => {
  const [messages, setMessages] = useState<AdventureMessage[]>([])
  const [input, setInput] = useState('')
  const [sending, setSending] = useState(false)
  const [loadingHistory, setLoadingHistory] = useState(true)
  const [pendingRoll, setPendingRoll] = useState<RollRequest | null>(null)
  const [rollValue, setRollValue] = useState('')
  const lastSentRef = useRef<
    | { type: 'message'; text: string }
    | { type: 'roll'; value: number; description: string }
    | null
  >(null)
  const messagesEndRef = useRef<HTMLDivElement>(null)
  const rollInputRef = useRef<HTMLInputElement>(null)

  const scrollToBottom = useCallback(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [])

  useEffect(() => { scrollToBottom() }, [messages, scrollToBottom])

  useEffect(() => {
    if (pendingRoll && rollInputRef.current) rollInputRef.current.focus()
  }, [pendingRoll])

  useEffect(() => {
    const loadHistory = async () => {
      try {
        const res = await fetch(`/adventures/${adventureId}/messages`, {
          headers: { Accept: 'application/json' },
        })
        if (!res.ok) throw new Error('Failed to load messages')
        const data: AdventureMessage[] = await res.json()
        setMessages(data)

        const lastDm = [...data].reverse().find(m => m.role === 'dm')
        if (lastDm?.message_type === 'roll_request' && lastDm.metadata?.roll_request) {
          const lastDmIdx = data.findIndex(m => m.id === lastDm.id)
          const hasRollResult = data.slice(lastDmIdx + 1).some(m => m.message_type === 'roll_result')
          if (!hasRollResult) setPendingRoll(lastDm.metadata.roll_request)
        }
      } catch (err) {
        console.error('Error loading chat history:', err)
      } finally {
        setLoadingHistory(false)
      }
    }
    loadHistory()
  }, [adventureId])

  // ---- Core send logic ----

  const sendMessage = async (text: string) => {
    setSending(true)
    setPendingRoll(null)
    lastSentRef.current = { type: 'message', text }

    const optimistic: AdventureMessage = {
      id: OPTIMISTIC_ID, role: 'player', content: text,
      message_type: 'narrative', metadata: {}, created_at: new Date().toISOString(),
    }
    const thinking: AdventureMessage = {
      id: THINKING_ID, role: 'dm', content: '',
      message_type: 'narrative', metadata: {}, created_at: new Date().toISOString(),
    }
    setMessages(prev => [...prev.filter(m => !isSentinel(m.id)), optimistic, thinking])

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
      setMessages(prev => [...prev.filter(m => !isSentinel(m.id)), ...data.messages])
      lastSentRef.current = null

      const dmMsg = data.messages.find(m => m.role === 'dm' && m.message_type === 'roll_request')
      if (dmMsg?.metadata?.roll_request) setPendingRoll(dmMsg.metadata.roll_request)

      if (onDmResponse) onDmResponse()

      const completeMsg = data.messages.find(m => m.message_type === 'adventure_complete')
      if (completeMsg && onAdventureComplete) onAdventureComplete()
    } catch (err: any) {
      console.error('Error sending message:', err)
      const errorMsg: AdventureMessage = {
        id: ERROR_ID, role: 'system', content: `Failed to send: ${err.message}`,
        message_type: 'narrative', metadata: {}, created_at: new Date().toISOString(),
      }
      setMessages(prev => [...prev.filter(m => m.id !== THINKING_ID && m.id !== ERROR_ID), errorMsg])
    } finally {
      setSending(false)
    }
  }

  const sendRoll = async (value: number, description: string) => {
    setSending(true)
    lastSentRef.current = { type: 'roll', value, description }

    const optimistic: AdventureMessage = {
      id: OPTIMISTIC_ID, role: 'player',
      content: `🎲 Rolled ${value} for: ${description}`,
      message_type: 'roll_result',
      metadata: { roll_value: value, roll_description: description },
      created_at: new Date().toISOString(),
    }
    const thinking: AdventureMessage = {
      id: THINKING_ID, role: 'dm', content: '',
      message_type: 'narrative', metadata: {}, created_at: new Date().toISOString(),
    }
    setMessages(prev => [...prev.filter(m => !isSentinel(m.id)), optimistic, thinking])

    try {
      const res = await fetch(`/adventures/${adventureId}/messages/roll`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken(),
          Accept: 'application/json',
        },
        body: JSON.stringify({ roll_value: value, roll_description: description }),
      })

      if (!res.ok) {
        const body = await res.json().catch(() => ({}))
        throw new Error(body.error || `HTTP ${res.status}`)
      }

      const data: { messages: AdventureMessage[] } = await res.json()
      setMessages(prev => [...prev.filter(m => !isSentinel(m.id)), ...data.messages])
      lastSentRef.current = null

      const dmMsg = data.messages.find(m => m.role === 'dm' && m.message_type === 'roll_request')
      if (dmMsg?.metadata?.roll_request) setPendingRoll(dmMsg.metadata.roll_request)

      if (onDmResponse) onDmResponse()

      const completeMsg = data.messages.find(m => m.message_type === 'adventure_complete')
      if (completeMsg && onAdventureComplete) onAdventureComplete()
    } catch (err: any) {
      console.error('Error submitting roll:', err)
      const errorMsg: AdventureMessage = {
        id: ERROR_ID, role: 'system', content: `Failed to submit roll: ${err.message}`,
        message_type: 'narrative', metadata: {}, created_at: new Date().toISOString(),
      }
      setMessages(prev => [...prev.filter(m => m.id !== THINKING_ID && m.id !== ERROR_ID), errorMsg])
    } finally {
      setSending(false)
    }
  }

  // ---- Handlers ----

  const handleSend = () => {
    const text = input.trim()
    if (!text || sending) return
    setInput('')
    sendMessage(text)
  }

  const handleRollSubmit = () => {
    const value = parseInt(rollValue, 10)
    if (isNaN(value) || value < 1 || !pendingRoll) return
    const description = pendingRoll.description
    setPendingRoll(null)
    setRollValue('')
    sendRoll(value, description)
  }

  const handleRetry = () => {
    const last = lastSentRef.current
    if (!last || sending) return
    if (last.type === 'message') sendMessage(last.text)
    else sendRoll(last.value, last.description)
  }

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      handleSend()
    }
  }

  // ---- Render ----

  return (
    <div className="adventure-chat">
      <h2>Dungeon Master</h2>

      <div className="chat-messages">
        {loadingHistory ? (
          <div className="chat-loading">Loading conversation...</div>
        ) : messages.length === 0 ? (
          <div className="chat-empty">
            <p>Your adventure awaits! Describe what your character does to begin.</p>
          </div>
        ) : (
          messages.map(msg => {
            if (msg.id === THINKING_ID) {
              return (
                <div key="thinking" className="chat-message msg-dm msg-thinking">
                  <div className="msg-header">
                    <span className="msg-role">🐉 DM</span>
                  </div>
                  <div className="thinking-dots">
                    <span /><span /><span />
                  </div>
                </div>
              )
            }

            return (
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
                {msg.id === ERROR_ID && (
                  <button className="retry-btn" onClick={handleRetry}>Retry</button>
                )}
              </div>
            )
          })
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
          ➤
        </button>
      </div>
    </div>
  )
}

export default AdventureChat
