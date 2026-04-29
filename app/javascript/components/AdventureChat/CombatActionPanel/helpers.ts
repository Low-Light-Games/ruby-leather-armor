import type { CombatAttackOption, CombatTarget } from '../../../services/combatActionService'
import type { AooEvent, NpcEvent, ParsedDiceExpression, ResolvedEntry } from './types'

export function normalizeDiceExpression(expression: string): string {
  return expression.trim().toLowerCase().replace(/\s+/g, '')
}

export function parseDiceExpression(expression: string): ParsedDiceExpression | null {
  const match = expression.match(/^(\d+)d(\d+)([+-]\d+)?$/)
  if (!match) return null
  return {
    count: parseInt(match[1], 10),
    sides: parseInt(match[2], 10),
    mod: match[3] ? parseInt(match[3], 10) : 0,
  }
}

export function rollParsedDice(parsed: ParsedDiceExpression): number {
  let total = parsed.mod
  for (let i = 0; i < parsed.count; i++) total += Math.floor(Math.random() * parsed.sides) + 1
  return Math.max(1, total)
}

export function rollDamageExpression(expression: string | null | undefined): number {
  if (!expression) return 0
  const parsed = parseDiceExpression(normalizeDiceExpression(expression))
  return parsed ? rollParsedDice(parsed) : 1
}

export function describeAttackOption(option: CombatAttackOption): string {
  const dmg = option.damage_type ? `${option.damage} ${option.damage_type}` : option.damage
  return `${option.label} — ${dmg}`
}

export function pickAliveTargetId(targets: CombatTarget[], previousId: number | null): number | null {
  const previousStillAlive = previousId != null && targets.some(t => t.creature_sheet_id === previousId && !t.dropped)
  if (previousStillAlive) return previousId

  const firstAlive = targets.find(t => !t.dropped)
  return firstAlive ? firstAlive.creature_sheet_id : null
}

export function makeResolvedEntry(
  suffix: string, message: string, hitFromPlayerPerspective: boolean, targetDropped: boolean,
): ResolvedEntry {
  return {
    id: `${Date.now()}-${Math.random()}-${suffix}`,
    message,
    hit: hitFromPlayerPerspective,
    target_dropped: targetDropped,
  }
}

export function entriesForAttackOfOpportunity(aoo: AooEvent, index: number): ResolvedEntry {
  return makeResolvedEntry(`aoo-${index}`, `AoO — ${aoo.message}`, !aoo.hit, aoo.target_dropped)
}

export function entriesForNpcEvent(evt: NpcEvent, index: number): ResolvedEntry {
  const message = evt.kind === 'npc_attack' && evt.outcome
    ? `${evt.creature_name} (${evt.kind}) — ${evt.outcome.message}`
    : evt.message || `${evt.creature_name} ${evt.kind}`
  const npcHit = evt.kind === 'npc_attack' && !!evt.outcome?.hit
  return makeResolvedEntry(`npc-${index}`, message, !npcHit, !!evt.outcome?.target_dropped)
}
