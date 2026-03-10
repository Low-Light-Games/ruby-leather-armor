import { useState, useEffect, useRef, useCallback } from 'react'
import { createConsumer } from '@rails/actioncable'
import type { AdventureMessage, DerivedStats } from '../../../types'
import { csrfToken } from '../../../utils/api'
import { buildPendingRollsFromMessage, PendingRolls } from '../rollHelpers'

const OPTIMISTIC_ID = -1
const THINKING_ID = -2
const ERROR_ID = -3

function isSentinel(id: number) {
  return id === OPTIMISTIC_ID || id === THINKING_ID || id === ERROR_ID
}

export { OPTIMISTIC_ID, THINKING_ID, ERROR_ID, isSentinel }

const cable = createConsumer()

interface UseAdventureMessagesArgs {
  adventureId: number
  derivedStats?: DerivedStats | null
  onAdventureComplete?: () => void
  onDmResponse?: () => void
}

export function useAdventureMessages({
  adventureId, derivedStats, onAdventureComplete, onDmResponse,
}: UseAdventureMessagesArgs) {
  const [messages, setMessages] = useState<AdventureMessage[]>([])
  const [sending, setSending] = useState(false)
  const [loadingHistory, setLoadingHistory] = useState(true)
  const [pendingRolls, setPendingRolls] = useState<PendingRolls | null>(null)

  const lastSentRef = useRef<
    | { type: 'message'; text: string }
    | { type: 'rolls'; rolls: Array<{ roll_value: number; roll_description: string }> }
    | null
  >(null)

  const activatePendingRolls = useCallback((msg: AdventureMessage) => {
    const rolls = buildPendingRollsFromMessage(msg, derivedStats)
    if (rolls) setPendingRolls(rolls)
  }, [derivedStats])

  const handleSyncResponse = useCallback((data: { messages: AdventureMessage[] }) => {
    setMessages(prev => [...prev.filter(m => !isSentinel(m.id)), ...data.messages])
    lastSentRef.current = null
    setSending(false)

    const dmMsg = data.messages.find(m => m.role === 'dm' && m.message_type === 'roll_request')
    if (dmMsg) activatePendingRolls(dmMsg)

    if (onDmResponse) onDmResponse()
    const completeMsg = data.messages.find(m => m.message_type === 'adventure_complete')
    if (completeMsg && onAdventureComplete) onAdventureComplete()
  }, [activatePendingRolls, onDmResponse, onAdventureComplete])

  const handleAsyncResponse = useCallback((data: { messages: AdventureMessage[] }) => {
    setMessages(prev => [
      ...prev.filter(m => m.id !== OPTIMISTIC_ID),
      ...data.messages,
    ])
  }, [])

  const handleError = useCallback((errorPrefix: string, err: any) => {
    console.error(`${errorPrefix}:`, err)
    const errorMsg: AdventureMessage = {
      id: ERROR_ID, role: 'system', content: `${errorPrefix}: ${err.message}`,
      message_type: 'narrative', metadata: {}, created_at: new Date().toISOString(),
    }
    setMessages(prev => [...prev.filter(m => m.id !== THINKING_ID && m.id !== ERROR_ID), errorMsg])
    setSending(false)
  }, [])

  // ActionCable subscription for async pipeline results
  useEffect(() => {
    const subscription = cable.subscriptions.create(
      { channel: 'AdventureChannel', adventure_id: adventureId },
      {
        received(data: { type: string; messages: AdventureMessage[] }) {
          if (data.type === 'pipeline_result' && data.messages) {
            handleSyncResponse(data)
          }
        },
      }
    )

    return () => { subscription.unsubscribe() }
  }, [adventureId, handleSyncResponse])

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

  const addOptimisticMessages = useCallback((
    playerContent: string,
    messageType: 'narrative' | 'roll_result',
    metadata?: Record<string, any>,
  ) => {
    const optimistic: AdventureMessage = {
      id: OPTIMISTIC_ID, role: 'player', content: playerContent,
      message_type: messageType, metadata: metadata || {}, created_at: new Date().toISOString(),
    }
    const thinking: AdventureMessage = {
      id: THINKING_ID, role: 'dm', content: '',
      message_type: 'narrative', metadata: {}, created_at: new Date().toISOString(),
    }
    setMessages(prev => [...prev.filter(m => !isSentinel(m.id)), optimistic, thinking])
  }, [])

  const sendMessage = async (text: string, mode?: string) => {
    setSending(true)
    setPendingRolls(null)
    lastSentRef.current = { type: 'message', text }
    addOptimisticMessages(text, 'narrative')

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
      if (data.async) handleAsyncResponse(data)
      else handleSyncResponse(data)
    } catch (err: any) {
      handleError('Failed to send', err)
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

    addOptimisticMessages(rollSummary, 'roll_result', { rolls })

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
      if (data.async) handleAsyncResponse(data)
      else handleSyncResponse(data)
    } catch (err: any) {
      handleError('Failed to submit rolls', err)
    }
  }

  const handleRetry = () => {
    const last = lastSentRef.current
    if (!last || sending) return
    if (last.type === 'message') sendMessage(last.text)
    else sendRolls(last.rolls)
  }

  return {
    messages, sending, loadingHistory,
    pendingRolls, setPendingRolls,
    sendMessage, sendRolls, handleRetry,
  }
}
