import { useState, useEffect, useRef, useCallback } from 'react'
import { createConsumer } from '@rails/actioncable'
import { AdventureMessage, RollRequest, DerivedStats, AdventureSheet } from '../../types'
import { csrfToken } from '../../utils/api'
import { formatMod } from '../../utils/formatting'
import { resolveRollRequest, ResolvedRoll } from '../../utils/rollResolver'
import { rollD20, DiceRollResult } from '../../rules/dice'
import RollResultModal, { RollResultDisplay } from '../RollResultModal'
import { useAuth } from '../../contexts/AuthContext'
import './AdventureChat.scss'

const OPTIMISTIC_ID = -1
const THINKING_ID = -2
const ERROR_ID = -3

function isSentinel(id: number) {
  return id === OPTIMISTIC_ID || id === THINKING_ID || id === ERROR_ID
}

const cable = createConsumer()

interface AdventureChatProps {
  adventureId: number
  derivedStats?: DerivedStats | null
  adventureSheet?: AdventureSheet | null
  onAdventureComplete?: () => void
  onDmResponse?: () => void
}

type ResolutionMethod = 'roll' | 'take_10' | 'take_20' | 'manual'

interface PendingRollEntry {
  request: RollRequest
  resolved: ResolvedRoll | null
  value: number | null
  resolution_method: ResolutionMethod | null
}

interface PendingRolls {
  requests: RollRequest[]
  entries: PendingRollEntry[]
  showDc: boolean
}

export const AdventureChat = ({ adventureId, derivedStats, adventureSheet, onAdventureComplete, onDmResponse }: AdventureChatProps) => {
  const { user } = useAuth()
  const [messages, setMessages] = useState<AdventureMessage[]>([])
  const [input, setInput] = useState('')
  const [askDm, setAskDm] = useState(false)
  const [sending, setSending] = useState(false)
  const [loadingHistory, setLoadingHistory] = useState(true)
  const [pendingRolls, setPendingRolls] = useState<PendingRolls | null>(null)
  const [rollModalDisplay, setRollModalDisplay] = useState<RollResultDisplay | null>(null)
  const [rollModalTargetIdx, setRollModalTargetIdx] = useState<number | null>(null)
  const lastSentRef = useRef<
    | { type: 'message'; text: string }
    | { type: 'rolls'; rolls: Array<{ roll_value: number; roll_description: string }> }
    | null
  >(null)
  const messagesEndRef = useRef<HTMLDivElement>(null)
  const rollInputRef = useRef<HTMLInputElement>(null)

  const scrollToBottom = useCallback(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [])

  useEffect(() => { scrollToBottom() }, [messages, scrollToBottom])

  useEffect(() => {
    if (pendingRolls && rollInputRef.current) rollInputRef.current.focus()
  }, [pendingRolls])

  // ActionCable subscription for async pipeline results
  useEffect(() => {
    const subscription = cable.subscriptions.create(
      { channel: 'AdventureChannel', adventure_id: adventureId },
      {
        received(data: { type: string; messages: AdventureMessage[] }) {
          if (data.type === 'pipeline_result' && data.messages) {
            setMessages(prev => [...prev.filter(m => !isSentinel(m.id)), ...data.messages])
            setSending(false)
            lastSentRef.current = null

            const dmMsg = data.messages.find(m => m.role === 'dm' && m.message_type === 'roll_request')
            if (dmMsg) activatePendingRolls(dmMsg)

            if (onDmResponse) onDmResponse()
            const completeMsg = data.messages.find(m => m.message_type === 'adventure_complete')
            if (completeMsg && onAdventureComplete) onAdventureComplete()
          }
        },
      }
    )

    return () => { subscription.unsubscribe() }
  }, [adventureId, onDmResponse, onAdventureComplete])

  // Load message history on mount
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
        if (lastDm?.message_type === 'roll_request') {
          const lastDmIdx = data.findIndex(m => m.id === lastDm.id)
          const hasRollResult = data.slice(lastDmIdx + 1).some(m => m.message_type === 'roll_result')
          if (!hasRollResult) {
            activatePendingRolls(lastDm)
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

  function extractRollRequests(msg: AdventureMessage): RollRequest[] {
    if (msg.metadata?.roll_requests && Array.isArray(msg.metadata.roll_requests)) {
      return msg.metadata.roll_requests
    }
    if (msg.metadata?.roll_request) {
      return [msg.metadata.roll_request]
    }
    return []
  }

  function rollLabel(req: RollRequest): string {
    const name = req.skill || req.type?.replace(/_/g, ' ') || 'Roll'
    if (req.domain) return `${name} (${req.domain.charAt(0).toUpperCase() + req.domain.slice(1)})`
    return name
  }

  function buildPendingRolls(requests: RollRequest[], showDc: boolean): PendingRolls {
    const entries: PendingRollEntry[] = requests.map(req => ({
      request: req,
      resolved: derivedStats ? resolveRollRequest(req, derivedStats) : null,
      value: null,
      resolution_method: null,
    }))
    return { requests, entries, showDc }
  }

  function activatePendingRolls(msg: AdventureMessage) {
    const requests = extractRollRequests(msg)
    if (requests.length > 0) {
      const showDc = msg.metadata?.show_dc !== false
      setPendingRolls(buildPendingRolls(requests, showDc))
    }
  }

  const sendMessage = async (text: string, mode?: string) => {
    setSending(true)
    setPendingRolls(null)
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
        body: JSON.stringify({ content: text, ...(mode && { mode }) }),
      })

      if (!res.ok) {
        const body = await res.json().catch(() => ({}))
        throw new Error(body.error || `HTTP ${res.status}`)
      }

      const data: { async?: boolean; messages: AdventureMessage[] } = await res.json()

      if (data.async) {
        // Async mode: replace optimistic with persisted player msg, keep thinking indicator.
        // ActionCable subscription will deliver DM response and clear sending state.
        setMessages(prev => [
          ...prev.filter(m => m.id !== OPTIMISTIC_ID),
          ...data.messages,
        ])
      } else {
        // Sync mode: full response inline
        setMessages(prev => [...prev.filter(m => !isSentinel(m.id)), ...data.messages])
        lastSentRef.current = null
        setSending(false)

        const dmMsg = data.messages.find(m => m.role === 'dm' && m.message_type === 'roll_request')
        if (dmMsg) activatePendingRolls(dmMsg)

        if (onDmResponse) onDmResponse()
        const completeMsg = data.messages.find(m => m.message_type === 'adventure_complete')
        if (completeMsg && onAdventureComplete) onAdventureComplete()
      }
    } catch (err: any) {
      console.error('Error sending message:', err)
      const errorMsg: AdventureMessage = {
        id: ERROR_ID, role: 'system', content: `Failed to send: ${err.message}`,
        message_type: 'narrative', metadata: {}, created_at: new Date().toISOString(),
      }
      setMessages(prev => [...prev.filter(m => m.id !== THINKING_ID && m.id !== ERROR_ID), errorMsg])
      setSending(false)
    }
  }

  const sendRolls = async (rolls: Array<{ roll_value: number; roll_description: string; resolution_method?: string }>) => {
    setSending(true)
    lastSentRef.current = { type: 'rolls', rolls }

    const rollSummary = rolls.map(r => {
      if (r.resolution_method === 'take_20') return `Take 20 (= ${r.roll_value}) for: ${r.roll_description}`
      if (r.resolution_method === 'take_10') return `Take 10 (= ${r.roll_value}) for: ${r.roll_description}`
      return `Rolled ${r.roll_value} for: ${r.roll_description}`
    }).join('\n')
    const optimistic: AdventureMessage = {
      id: OPTIMISTIC_ID, role: 'player', content: rollSummary,
      message_type: 'roll_result', metadata: { rolls }, created_at: new Date().toISOString(),
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
        body: JSON.stringify({ rolls }),
      })

      if (!res.ok) {
        const body = await res.json().catch(() => ({}))
        throw new Error(body.error || `HTTP ${res.status}`)
      }

      const data: { async?: boolean; messages: AdventureMessage[] } = await res.json()

      if (data.async) {
        setMessages(prev => [
          ...prev.filter(m => m.id !== OPTIMISTIC_ID),
          ...data.messages,
        ])
      } else {
        setMessages(prev => [...prev.filter(m => !isSentinel(m.id)), ...data.messages])
        lastSentRef.current = null
        setSending(false)

        const dmMsg = data.messages.find(m => m.role === 'dm' && m.message_type === 'roll_request')
        if (dmMsg) activatePendingRolls(dmMsg)

        if (onDmResponse) onDmResponse()
        const completeMsg = data.messages.find(m => m.message_type === 'adventure_complete')
        if (completeMsg && onAdventureComplete) onAdventureComplete()
      }
    } catch (err: any) {
      console.error('Error submitting rolls:', err)
      const errorMsg: AdventureMessage = {
        id: ERROR_ID, role: 'system', content: `Failed to submit rolls: ${err.message}`,
        message_type: 'narrative', metadata: {}, created_at: new Date().toISOString(),
      }
      setMessages(prev => [...prev.filter(m => m.id !== THINKING_ID && m.id !== ERROR_ID), errorMsg])
      setSending(false)
    }
  }

  const handleSend = () => {
    const text = input.trim()
    if (!text || sending) return
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

  const handleManualRollChange = (index: number, raw: string) => {
    const v = parseInt(raw, 10)
    setRollValue(index, isNaN(v) ? 0 : v, 'manual')
  }

  const handleRollD20 = (index: number) => {
    if (!pendingRolls) return
    const entry = pendingRolls.entries[index]
    if (!entry.resolved) return

    const result = rollD20(entry.resolved.modifier)
    setRollModalTargetIdx(index)
    setRollModalDisplay({
      label: entry.resolved.label,
      result,
      modifierLabel: entry.resolved.modifierLabel,
    })
  }

  const handleTake = (index: number, takeValue: number, method: ResolutionMethod) => {
    setRollValue(index, takeValue, method)
  }

  const handleRollModalClose = () => {
    if (rollModalDisplay && rollModalTargetIdx != null) {
      setRollValue(rollModalTargetIdx, rollModalDisplay.result.total, 'roll')
    }
    setRollModalDisplay(null)
    setRollModalTargetIdx(null)
  }

  const allRollsFilled = pendingRolls?.entries.every(e => e.value != null && e.value >= 1) ?? false

  const handleRollsSubmit = () => {
    if (!pendingRolls || !allRollsFilled) return

    const rolls = pendingRolls.entries.map(e => ({
      roll_value: e.value!,
      roll_description: e.request.description,
      resolution_method: e.resolution_method || 'manual',
    }))

    setPendingRolls(null)
    sendRolls(rolls)
  }

  const handleRetry = () => {
    const last = lastSentRef.current
    if (!last || sending) return
    if (last.type === 'message') sendMessage(last.text)
    else sendRolls(last.rolls)
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

            const rollRequests = msg.message_type === 'roll_request' ? extractRollRequests(msg) : []
            const msgShowDc = msg.metadata?.show_dc !== false

            return (
              <div
                key={msg.id}
                className={`chat-message msg-${msg.role} msg-type-${msg.message_type}`}
              >
                <div className="msg-header">
                  <span className="msg-role">
                    {msg.role === 'player' ? '🗡️ You' : msg.role === 'dm' ? '🐉 DM' : '📜 System'}
                  </span>
                  {user?.admin && msg.pipeline_run_id && (
                    <a
                      href={`/admin/ai_logs/pipelines/${msg.pipeline_run_id}`}
                      className="pipeline-id-link"
                      target="_blank"
                      rel="noopener noreferrer"
                      title="View pipeline run"
                    >
                      {msg.pipeline_run_id.slice(0, 8)}…
                    </a>
                  )}
                </div>
                <div className="msg-content">{msg.content}</div>
                {rollRequests.length > 0 && (
                  <div className="roll-request-badges">
                    {rollRequests.map((req, i) => (
                      <div key={i} className="roll-request-badge">
                        <span className="roll-badge-label">🎲 {rollLabel(req)}</span>
                        {msgShowDc && req.dc != null && <span className="roll-dc">DC {req.dc}</span>}
                        <span className="roll-badge-desc">{req.description}</span>
                      </div>
                    ))}
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

      {pendingRolls && !sending && (
        <div className="roll-submit-area">
          <div className="roll-prompt-header">🎲 Rolls Needed</div>
          {pendingRolls.entries.map((entry, i) => {
            const { request: req, resolved, value } = entry
            const isHallucination = derivedStats && !resolved

            return (
              <div key={i} className={`roll-entry ${isHallucination ? 'roll-unresolved' : ''}`}>
                <div className="roll-prompt">
                  <span className="roll-prompt-type">
                    {resolved ? resolved.label : rollLabel(req)}
                  </span>
                  {pendingRolls.showDc && req.dc != null && <span className="roll-dc">DC {req.dc}</span>}
                  <span className="roll-prompt-desc">{req.description}</span>
                  {resolved && (
                    <span className="roll-modifier">{formatMod(resolved.modifier)}</span>
                  )}
                  {isHallucination && (
                    <span className="roll-warning">Not on character sheet</span>
                  )}
                </div>
                <div className="roll-actions">
                  {resolved ? (
                    <>
                      <button
                        className={`roll-btn roll-d20 ${value != null ? 'roll-done' : ''}`}
                        onClick={() => handleRollD20(i)}
                        disabled={value != null}
                      >
                        {value != null ? `Rolled: ${value}` : `Roll (${formatMod(resolved.modifier)})`}
                      </button>
                      {req.take_10_eligible && req.take_10_value != null && value == null && (
                        <button
                          className="roll-btn roll-take"
                          onClick={() => handleTake(i, req.take_10_value!, 'take_10')}
                        >
                          Take 10 (= {req.take_10_value})
                        </button>
                      )}
                      {req.take_20_eligible && req.take_20_value != null && value == null && (
                        <button
                          className="roll-btn roll-take"
                          onClick={() => handleTake(i, req.take_20_value!, 'take_20')}
                        >
                          Take 20 (= {req.take_20_value})
                        </button>
                      )}
                    </>
                  ) : (
                    <input
                      ref={i === 0 ? rollInputRef : undefined}
                      type="number"
                      min="1"
                      max="100"
                      placeholder="Roll result"
                      value={value ?? ''}
                      onChange={e => handleManualRollChange(i, e.target.value)}
                      onKeyDown={e => {
                        if (e.key === 'Enter' && allRollsFilled) handleRollsSubmit()
                      }}
                      className="roll-input"
                    />
                  )}
                </div>
              </div>
            )
          })}
          <button
            onClick={handleRollsSubmit}
            disabled={!allRollsFilled}
            className="roll-submit-btn"
          >
            Submit {pendingRolls.entries.length > 1 ? 'All Rolls' : 'Roll'}
          </button>
        </div>
      )}

      <RollResultModal
        roll={rollModalDisplay}
        onClose={handleRollModalClose}
      />

      <div className="chat-input-area">
        <button
          type="button"
          className={`ask-dm-toggle ${askDm ? 'active' : ''}`}
          onClick={() => setAskDm(prev => !prev)}
          disabled={sending}
          title="Toggle to ask the Dungeon Master for help, rules clarifications, or information about the game world — without taking an action."
        >
          ❓ Ask DM
        </button>
        <div className="chat-input-wrapper">
          <textarea
            value={input}
            onChange={e => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder={askDm ? 'Ask the DM a question...' : (pendingRolls ? 'Submit your rolls above, or describe another action...' : 'What does your character do?')}
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
    </div>
  )
}

export default AdventureChat
