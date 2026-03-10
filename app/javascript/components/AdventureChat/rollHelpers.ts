import type { AdventureMessage, RollRequest, DerivedStats } from '../../types'
import { resolveRollRequest, ResolvedRoll } from '../../utils/rollResolver'

export type ResolutionMethod = 'roll' | 'take_10' | 'take_20' | 'manual'

export interface PendingRollEntry {
  request: RollRequest
  resolved: ResolvedRoll | null
  value: number | null
  resolution_method: ResolutionMethod | null
}

export interface PendingRolls {
  requests: RollRequest[]
  entries: PendingRollEntry[]
  showDc: boolean
}

export function extractRollRequests(msg: AdventureMessage): RollRequest[] {
  if (msg.metadata?.roll_requests && Array.isArray(msg.metadata.roll_requests)) {
    return msg.metadata.roll_requests
  }
  if (msg.metadata?.roll_request) {
    return [msg.metadata.roll_request]
  }
  return []
}

export function rollLabel(req: RollRequest): string {
  const name = req.skill || req.type?.replace(/_/g, ' ') || 'Roll'
  if (req.domain) return `${name} (${req.domain.charAt(0).toUpperCase() + req.domain.slice(1)})`
  return name
}

export function buildPendingRolls(
  requests: RollRequest[],
  showDc: boolean,
  derivedStats?: DerivedStats | null,
): PendingRolls {
  const entries: PendingRollEntry[] = requests.map(req => ({
    request: req,
    resolved: derivedStats ? resolveRollRequest(req, derivedStats) : null,
    value: null,
    resolution_method: null,
  }))
  return { requests, entries, showDc }
}

export function buildPendingRollsFromMessage(
  msg: AdventureMessage,
  derivedStats?: DerivedStats | null,
): PendingRolls | null {
  const requests = extractRollRequests(msg)
  if (requests.length === 0) return null
  const showDc = msg.metadata?.show_dc !== false
  return buildPendingRolls(requests, showDc, derivedStats)
}
