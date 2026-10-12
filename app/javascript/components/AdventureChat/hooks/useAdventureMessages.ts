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

type MessageBatch = { messages: AdventureMessage[] }
type MessageHistory = MessageBatch & { pipeline_running: boolean }
type ActionResponse = MessageBatch & { async?: boolean }
type RollSubmission = { roll_value: number; roll_description: string; request_id?: string; resolution_method?: string }

async function fetchMessageHistory(adventureId: number, failureMessage: string): Promise<MessageHistory> {
  const res = await fetch(`/adventures/${adventureId}/messages`, {
    headers: { Accept: 'application/json' },
  })
  if (!res.ok) throw new Error(failureMessage)
  return res.json()
}

async function postAdventureAction(path: string, payload: object): Promise<ActionResponse> {
  const res = await fetch(path, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-CSRF-Token': csrfToken(),
      Accept: 'application/json',
    },
    body: JSON.stringify(payload),
  })

  if (!res.ok) {
    const body = await res.json().catch(() => ({}))
    throw new Error(body.error || `HTTP ${res.status}`)
  }

  return res.json()
}

function findDmMessage(messages: AdventureMessage[], messageType: 'roll_request' | 'initiative_request') {
  return messages.find(m => m.role === 'dm' && m.message_type === messageType)
}

function endsAdventure(messages: AdventureMessage[]) {
  return messages.some(m => m.message_type === 'adventure_complete' || m.message_type === 'player_death')
}

function withoutSentinels(messages: AdventureMessage[]) {
  return messages.filter(m => !isSentinel(m.id))
}

// The thinking indicator stays last until the final pipeline_result removes it.
function insertBeforeThinking(messages: AdventureMessage[], incoming: AdventureMessage[]) {
  const thinking = messages.find(m => m.id === THINKING_ID)
  const rest = withoutSentinels(messages)
  return thinking ? [...rest, ...incoming, thinking] : [...rest, ...incoming]
}

function thinkingMessage(): AdventureMessage {
  return {
    id: THINKING_ID,
    role: 'dm',
    content: '',
    message_type: 'narrative',
    metadata: {},
    created_at: new Date().toISOString(),
  }
}

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

function shouldShowThinking(messages: AdventureMessage[], pipelineRunning: boolean) {
  if (pipelineRunning) return true

  const lastMessage = messages[messages.length - 1]
  return lastMessage?.role === 'player'
}

function withThinkingSentinel(messages: AdventureMessage[], thinking: boolean): AdventureMessage[] {
  if (!thinking) return messages

  return [...messages, thinkingMessage()]
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
    | { type: 'rolls'; rolls: RollSubmission[] }
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

  const handleSyncResponse = useCallback((data: MessageBatch) => {
    setMessages(prev => [...withoutSentinels(prev), ...data.messages])
    lastSentRef.current = null
    setSending(false)

    const rollRequest = findDmMessage(data.messages, 'roll_request')
    if (rollRequest) activatePendingRolls(rollRequest)
    if (findDmMessage(data.messages, 'initiative_request')) setPendingInitiative(true)

    if (onDmResponse) onDmResponse()
    if (endsAdventure(data.messages) && onAdventureComplete) onAdventureComplete()
  }, [activatePendingRolls, onDmResponse, onAdventureComplete])

  const handleAsyncResponse = useCallback((data: MessageBatch) => {
    setMessages(prev => insertBeforeThinking(prev, data.messages))
  }, [])

  const handleActionResult = useCallback((data: MessageBatch) => {
    setMessages(prev => insertBeforeThinking(prev, data.messages))
    if (endsAdventure(data.messages) && onAdventureComplete) onAdventureComplete()
  }, [onAdventureComplete])

  const handleError = useCallback((errorPrefix: string, err: any) => {
    console.error(`${errorPrefix}:`, err)
    const errorMsg: AdventureMessage = {
      id: ERROR_ID, role: 'system', content: `${errorPrefix}: ${err.message}`,
      message_type: 'narrative', metadata: {}, created_at: new Date().toISOString(),
    }
    setMessages(prev => [...withoutSentinels(prev), errorMsg])
    setSending(false)
  }, [])

  const reloadAuthoritativeMessages = useCallback(async () => {
    const data = await fetchMessageHistory(adventureId, 'Failed to reload messages')
    const thinking = shouldShowThinking(data.messages, data.pipeline_running)
    setMessages(withThinkingSentinel(data.messages, thinking))
    setSending(thinking)
  }, [adventureId])

  // Resubscribing would briefly deliver every broadcast twice, so the subscription reads handlers from here.
  const handlersRef = useRef({
    handleSyncResponse,
    handleActionResult,
    handleProgressUpdate,
    onSheetUpdate,
    activatePendingRolls,
    onDmResponse,
    onAdventureComplete,
  })

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
    const authoritativeMessages = withoutSentinels(messages)
    const nextState = derivePendingInteractionState(authoritativeMessages, derivedStats)
    setPendingRolls(nextState.pendingRolls)
    setPendingInitiative(nextState.pendingInitiative)
  }, [messages]) // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    const adoptHistoryMissedWhileDisconnected = (history: MessageHistory) => {
      const h = handlersRef.current
      const rollRequest = findDmMessage(history.messages, 'roll_request')
      if (rollRequest) h.activatePendingRolls(rollRequest)
      if (findDmMessage(history.messages, 'initiative_request')) setPendingInitiative(true)

      setMessages(history.messages)
      setSending(false)
      lastSentRef.current = null
      if (h.onDmResponse) h.onDmResponse()
      if (endsAdventure(history.messages) && h.onAdventureComplete) h.onAdventureComplete()
    }

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
          if (!sendingRef.current) return

          fetchMessageHistory(adventureId, 'Failed to reload messages')
            .then(history => {
              // A running pipeline still broadcasts its results; replacing the list
              // now would duplicate the progressive messages already shown.
              if (!sendingRef.current || history.pipeline_running) return

              adoptHistoryMissedWhileDisconnected(history)
            })
            .catch(() => {})
        },
      }
    )

    return () => { subscription.unsubscribe() }
  }, [adventureId]) // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    const loadHistory = async () => {
      try {
        const data = await fetchMessageHistory(adventureId, 'Failed to load messages')
        const thinking = shouldShowThinking(data.messages, data.pipeline_running)
        setMessages(withThinkingSentinel(data.messages, thinking))
        setSending(thinking)
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
    setMessages(prev => [...withoutSentinels(prev), optimistic, thinkingMessage()])
  }, [])

  const sendMessage = async (text: string) => {
    setSending(true)
    setPendingRolls(null)
    lastSentRef.current = { type: 'message', text }
    addOptimisticMessages(text, 'narrative')

    try {
      const data = await postAdventureAction(`/adventures/${adventureId}/messages`, { content: text })
      setPendingRolls(null)
      if (data.async) handleAsyncResponse(data)
      else handleSyncResponse(data)
    } catch (err: any) {
      handleError('Failed to send', err)
    }
  }

  const sendRolls = async (rolls: RollSubmission[]) => {
    setSending(true)
    lastSentRef.current = { type: 'rolls', rolls }

    const rollSummary = rolls.map(r => {
      if (r.resolution_method === 'take_20') return `Take 20 (= ${r.roll_value}) for: ${r.roll_description}`
      if (r.resolution_method === 'take_10') return `Take 10 (= ${r.roll_value}) for: ${r.roll_description}`
      return `Rolled ${r.roll_value} for: ${r.roll_description}`
    }).join('\n')

    addOptimisticMessages(rollSummary, 'roll_result', { rolls })

    try {
      const data = await postAdventureAction(`/adventures/${adventureId}/messages/roll`, { rolls })
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
      const data = await postAdventureAction(`/adventures/${adventureId}/messages/initiative`, { initiative: value })
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
