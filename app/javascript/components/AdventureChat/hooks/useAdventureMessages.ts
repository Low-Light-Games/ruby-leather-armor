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

function findLastIndex<T>(items: T[], predicate: (item: T) => boolean) {
  for (let i = items.length - 1; i >= 0; i -= 1) {
    if (predicate(items[i])) return i
  }
  return -1
}

function derivePendingInteractionState(
  messages: AdventureMessage[],
  derivedStats?: DerivedStats | null,
) {
  const latestRollRequestIndex = findLastIndex(
    messages,
    m => m.role === 'dm' && m.message_type === 'roll_request',
  )
  const latestInitiativeRequestIndex = findLastIndex(
    messages,
    m => m.role === 'dm' && m.message_type === 'initiative_request',
  )

  const unresolvedRollRequestIndex = latestRollRequestIndex >= 0 &&
    !messages.slice(latestRollRequestIndex + 1).some(m => m.message_type === 'roll_result')
    ? latestRollRequestIndex
    : -1

  const unresolvedInitiativeRequestIndex = latestInitiativeRequestIndex >= 0 &&
    !messages.slice(latestInitiativeRequestIndex + 1).some(m => m.message_type === 'initiative_result')
    ? latestInitiativeRequestIndex
    : -1

  if (unresolvedRollRequestIndex > unresolvedInitiativeRequestIndex) {
    return {
      pendingRolls: buildPendingRollsFromMessage(messages[unresolvedRollRequestIndex], derivedStats),
      pendingInitiative: false,
    }
  }

  if (unresolvedInitiativeRequestIndex > unresolvedRollRequestIndex) {
    return { pendingRolls: null, pendingInitiative: true }
  }

  return { pendingRolls: null, pendingInitiative: false }
}

interface UseAdventureMessagesArgs {
  adventureId: number
  derivedStats?: DerivedStats | null
  onAdventureComplete?: () => void
  onDmResponse?: () => void
  onSheetUpdate?: () => void
}

export function useAdventureMessages({
  adventureId, derivedStats, onAdventureComplete, onDmResponse, onSheetUpdate,
}: UseAdventureMessagesArgs) {
  const [messages, setMessages] = useState<AdventureMessage[]>([])
  const [sending, setSending] = useState(false)
  const [loadingHistory, setLoadingHistory] = useState(true)
  const [pendingRolls, setPendingRolls] = useState<PendingRolls | null>(null)
  const [pendingInitiative, setPendingInitiative] = useState(false)

  const lastSentRef = useRef<
    | { type: 'message'; text: string }
    | { type: 'rolls'; rolls: Array<{ roll_value: number; roll_description: string; request_id?: string; resolution_method?: string }> }
    | { type: 'initiative'; value: number }
    | null
  >(null)

  const sendingRef = useRef(false)
  useEffect(() => { sendingRef.current = sending }, [sending])

  const activatePendingRolls = useCallback((msg: AdventureMessage) => {
    const rolls = buildPendingRollsFromMessage(msg, derivedStats)
    if (rolls) setPendingRolls(rolls)
  }, [derivedStats])

  const handleProgressUpdate = useCallback((message: string) => {
    setMessages(prev => prev.map(m => m.id === THINKING_ID ? { ...m, content: message } : m))
  }, [])

  const handleSyncResponse = useCallback((data: { messages: AdventureMessage[] }) => {
    setMessages(prev => [...prev.filter(m => !isSentinel(m.id)), ...data.messages])
    lastSentRef.current = null
    setSending(false)

    const dmMsg = data.messages.find(m => m.role === 'dm' && m.message_type === 'roll_request')
    if (dmMsg) activatePendingRolls(dmMsg)

    const initMsg = data.messages.find(m => m.role === 'dm' && m.message_type === 'initiative_request')
    if (initMsg) setPendingInitiative(true)

    if (onDmResponse) onDmResponse()
    const completeMsg = data.messages.find(m => m.message_type === 'adventure_complete')
    const deathMsg = data.messages.find(m => m.message_type === 'player_death')
    if ((completeMsg || deathMsg) && onAdventureComplete) onAdventureComplete()
  }, [activatePendingRolls, onDmResponse, onAdventureComplete])

  const handleAsyncResponse = useCallback((data: { messages: AdventureMessage[] }) => {
    setMessages(prev => {
      const thinking = prev.find(m => m.id === THINKING_ID)
      const rest = prev.filter(m => !isSentinel(m.id))
      return thinking
        ? [...rest, ...data.messages, thinking]
        : [...rest, ...data.messages]
    })
  }, [])

  // Progressive per-action narration: insert messages before the thinking sentinel
  // so the player sees each action result as it arrives. The thinking indicator
  // stays visible until the final empty pipeline_result "done" signal removes it.
  const handleActionResult = useCallback((data: { messages: AdventureMessage[] }) => {
    setMessages(prev => {
      const thinking = prev.find(m => m.id === THINKING_ID)
      const rest = prev.filter(m => !isSentinel(m.id))
      return thinking
        ? [...rest, ...data.messages, thinking]
        : [...rest, ...data.messages]
    })
    const completeMsg = data.messages.find(m => m.message_type === 'adventure_complete')
    const deathMsg = data.messages.find(m => m.message_type === 'player_death')
    if ((completeMsg || deathMsg) && onAdventureComplete) onAdventureComplete()
  }, [onAdventureComplete])

  const handleError = useCallback((errorPrefix: string, err: any) => {
    console.error(`${errorPrefix}:`, err)
    const errorMsg: AdventureMessage = {
      id: ERROR_ID, role: 'system', content: `${errorPrefix}: ${err.message}`,
      message_type: 'narrative', metadata: {}, created_at: new Date().toISOString(),
    }
    setMessages(prev => [...prev.filter(m => !isSentinel(m.id)), errorMsg])
    setSending(false)
  }, [])

  const reloadAuthoritativeMessages = useCallback(async () => {
    const res = await fetch(`/adventures/${adventureId}/messages`, {
      headers: { Accept: 'application/json' },
    })
    if (!res.ok) throw new Error('Failed to reload messages')

    const data: { messages: AdventureMessage[]; pipeline_running: boolean } = await res.json()
    setMessages(data.messages)
    setSending(false)
  }, [adventureId])

  // Stable ref that always holds the latest handler versions. The subscription
  // effect closes over this ref (not the handlers directly) so it never needs
  // to be recreated when callbacks or derivedStats change — which would briefly
  // produce two simultaneous server-side subscriptions and deliver every
  // broadcast event twice.
  const handlersRef = useRef({
    handleSyncResponse,
    handleActionResult,
    handleProgressUpdate,
    onSheetUpdate,
    activatePendingRolls,
    onDmResponse,
    onAdventureComplete,
  })

  // Keep the ref current on every render so the subscription always calls the
  // latest versions without being recreated.
  useEffect(() => {
    handlersRef.current = {
      handleSyncResponse,
      handleActionResult,
      handleProgressUpdate,
      onSheetUpdate,
      activatePendingRolls,
      onDmResponse,
      onAdventureComplete,
    }
  })

  useEffect(() => {
    const authoritativeMessages = messages.filter(m => !isSentinel(m.id))
    const nextState = derivePendingInteractionState(authoritativeMessages, derivedStats)
    setPendingRolls(nextState.pendingRolls)
    setPendingInitiative(nextState.pendingInitiative)
  }, [messages]) // eslint-disable-line react-hooks/exhaustive-deps

  // ActionCable subscription for async pipeline results.
  // Depends ONLY on adventureId — never recreated due to callback churn,
  // which would produce a brief window of two server-side subscriptions
  // and deliver every broadcast event twice.
  useEffect(() => {
    const subscription = cable.subscriptions.create(
      { channel: 'AdventureChannel', adventure_id: adventureId },
      {
        received(data: { type: string; messages: AdventureMessage[]; message?: string }) {
          const h = handlersRef.current
          if (data.type === 'pipeline_result' && data.messages) {
            h.handleSyncResponse(data)
          } else if (data.type === 'pipeline_action_result' && data.messages) {
            h.handleActionResult(data)
          } else if (data.type === 'pipeline_progress' && data.message) {
            h.handleProgressUpdate(data.message)
          } else if (data.type === 'sheet_update') {
            h.onSheetUpdate?.()
          }
        },

        connected() {
          // On reconnect while waiting for a response, re-fetch to recover
          // any pipeline results that arrived during the disconnect window.
          if (!sendingRef.current) return

          fetch(`/adventures/${adventureId}/messages`, { headers: { Accept: 'application/json' } })
            .then(r => r.ok ? r.json() : null)
            .then((data: { messages: AdventureMessage[]; pipeline_running: boolean } | null) => {
              if (!data || !sendingRef.current) return

              // Pipeline still running — WebSocket events will deliver results as
              // they arrive. Do NOT call handleSyncResponse here: it would append
              // already-present progressive messages and set sending=false early.
              if (data.pipeline_running) return

              // Pipeline finished during the disconnect window. Replace state with
              // the server's authoritative list to avoid duplicating any messages
              // that were already appended via pipeline_action_result events.
              const msgs = data.messages
              const h = handlersRef.current
              const dmMsg = msgs.find(m => m.role === 'dm' && m.message_type === 'roll_request')
              if (dmMsg) h.activatePendingRolls(dmMsg)
              const initMsg = msgs.find(m => m.role === 'dm' && m.message_type === 'initiative_request')
              if (initMsg) setPendingInitiative(true)

              setMessages(msgs)
              setSending(false)
              lastSentRef.current = null
              if (h.onDmResponse) h.onDmResponse()
              const completeMsg = msgs.find(m => m.message_type === 'adventure_complete')
              const deathMsg = msgs.find(m => m.message_type === 'player_death')
              if ((completeMsg || deathMsg) && h.onAdventureComplete) h.onAdventureComplete()
            })
            .catch(() => {})
        },
      }
    )

    return () => { subscription.unsubscribe() }
  }, [adventureId]) // eslint-disable-line react-hooks/exhaustive-deps

  // Load message history on mount
  useEffect(() => {
    const loadHistory = async () => {
      try {
        const res = await fetch(`/adventures/${adventureId}/messages`, {
          headers: { Accept: 'application/json' },
        })
        if (!res.ok) throw new Error('Failed to load messages')
        const data: { messages: AdventureMessage[]; pipeline_running: boolean } = await res.json()
        const msgs = data.messages

        if (data.pipeline_running) {
          // Pipeline is still running (e.g. player refreshed mid-turn).
          // Restore the thinking indicator so the player knows the GM is still working.
          const thinkingSentinel: AdventureMessage = {
            id: THINKING_ID, role: 'dm', content: '',
            message_type: 'narrative', metadata: {}, created_at: new Date().toISOString(),
          }
          setMessages([...msgs, thinkingSentinel])
          setSending(true)
        } else {
          setMessages(msgs)
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
    messageType: 'narrative' | 'roll_result' | 'initiative_result',
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
      setPendingRolls(null)
      if (data.async) handleAsyncResponse(data)
      else handleSyncResponse(data)
    } catch (err: any) {
      handleError('Failed to send', err)
    }
  }

  const sendRolls = async (rolls: Array<{ roll_value: number; roll_description: string; request_id?: string; resolution_method?: string }>) => {
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
      await reloadAuthoritativeMessages().catch(() => {})
      handleError('Failed to submit rolls', err)
    }
  }

  const sendInitiative = async (value: number) => {
    setSending(true)
    lastSentRef.current = { type: 'initiative', value }

    addOptimisticMessages(`Rolled ${value} for initiative`, 'initiative_result', { initiative: value })

    try {
      const res = await fetch(`/adventures/${adventureId}/messages/initiative`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken(),
          Accept: 'application/json',
        },
        body: JSON.stringify({ initiative: value }),
      })

      if (!res.ok) {
        const body = await res.json().catch(() => ({}))
        throw new Error(body.error || `HTTP ${res.status}`)
      }

      const data: { async?: boolean; messages: AdventureMessage[] } = await res.json()
      if (data.async) handleAsyncResponse(data)
      else handleSyncResponse(data)
    } catch (err: any) {
      await reloadAuthoritativeMessages().catch(() => {})
      handleError('Failed to submit initiative', err)
    }
  }

  const handleRetry = () => {
    const last = lastSentRef.current
    if (!last || sending) return
    if (last.type === 'message') sendMessage(last.text)
    else if (last.type === 'rolls') sendRolls(last.rolls)
    else sendInitiative(last.value)
  }

  return {
    messages, sending, loadingHistory,
    pendingRolls, setPendingRolls,
    pendingInitiative, setPendingInitiative,
    sendMessage, sendRolls, sendInitiative, handleRetry,
  }
}
