import { useMemo } from 'react'
import type { BattlefieldSnapshot } from '../../types'
import type { CombatTarget } from '../../services/combatActionService'

interface Props {
  battlefield: BattlefieldSnapshot
  playerPosition: { x: number; y: number } | null
  speedSquares: number
  canMove: boolean
  canWithdraw: boolean
  withdrawMode: boolean
  onWithdrawToggle: () => void
  onSquareClick: (x: number, y: number) => void
  busy: boolean
  targets?: CombatTarget[]
}

interface ResolvedToken {
  id: string
  label: string
  displayLabel: string
  x: number
  y: number
  type: string
  creatureSheetId: number | null
  isPlayer: boolean
}

const CELL_PX = 24
const MAX_GRID_PX = 360

function readViewport(viewport: Record<string, unknown>): { minX: number; minY: number; width: number; height: number } {
  const minX = typeof viewport.min_x === 'number' ? viewport.min_x : 0
  const minY = typeof viewport.min_y === 'number' ? viewport.min_y : 0
  const width = typeof viewport.width === 'number' && viewport.width > 0 ? viewport.width : 20
  const height = typeof viewport.height === 'number' && viewport.height > 0 ? viewport.height : 20
  return { minX, minY, width, height }
}

function readTokens(tokens: Record<string, Record<string, unknown>>): ResolvedToken[] {
  const intermediate: Omit<ResolvedToken, 'displayLabel'>[] = []
  for (const [id, raw] of Object.entries(tokens)) {
    if (!raw || typeof raw !== 'object') continue
    const x = typeof raw.x === 'number' ? raw.x : null
    const y = typeof raw.y === 'number' ? raw.y : null
    if (x == null || y == null) continue
    const csid = typeof raw.creature_sheet_id === 'number' ? raw.creature_sheet_id : null
    intermediate.push({
      id,
      label: typeof raw.label === 'string' ? raw.label : id,
      x,
      y,
      type: typeof raw.type === 'string' ? raw.type : 'npc',
      creatureSheetId: csid,
      isPlayer: id === 'player',
    })
  }

  // Disambiguate same-name NPCs with a #N suffix (Goblin → "Goblin #1",
  // "Goblin #2") so the tooltip can tell two of the same kind apart.
  const labelCounts = new Map<string, number>()
  intermediate.forEach(t => {
    if (t.isPlayer) return
    labelCounts.set(t.label, (labelCounts.get(t.label) || 0) + 1)
  })
  const labelSeen = new Map<string, number>()
  return intermediate.map(t => {
    if (t.isPlayer || (labelCounts.get(t.label) || 0) <= 1) {
      return { ...t, displayLabel: t.label }
    }
    const seen = (labelSeen.get(t.label) || 0) + 1
    labelSeen.set(t.label, seen)
    return { ...t, displayLabel: `${t.label} #${seen}` }
  })
}

function findCreatureHp(targets: CombatTarget[] | undefined, creatureSheetId: number | null) {
  if (!targets || creatureSheetId == null) return null
  return targets.find(t => t.creature_sheet_id === creatureSheetId) || null
}

export const CombatGrid = ({
  battlefield, playerPosition, speedSquares, canMove, canWithdraw, withdrawMode,
  onWithdrawToggle, onSquareClick, busy, targets,
}: Props) => {
  const viewport = useMemo(() => readViewport(battlefield.viewport), [battlefield.viewport])
  const tokens = useMemo(() => readTokens(battlefield.tokens), [battlefield.tokens])

  const tightView = useMemo(() => {
    if (tokens.length === 0) return viewport
    const xs = tokens.map(t => t.x)
    const ys = tokens.map(t => t.y)
    const pad = Math.max(speedSquares, 3)
    const minX = Math.min(...xs) - pad
    const maxX = Math.max(...xs) + pad
    const minY = Math.min(...ys) - pad
    const maxY = Math.max(...ys) + pad
    return { minX, minY, width: maxX - minX + 1, height: maxY - minY + 1 }
  }, [tokens, speedSquares, viewport])

  const cellPx = useMemo(() => {
    const widest = Math.max(tightView.width, tightView.height)
    if (widest <= 0) return CELL_PX
    return Math.max(12, Math.min(CELL_PX, Math.floor(MAX_GRID_PX / widest)))
  }, [tightView.width, tightView.height])

  const occupied = useMemo(() => {
    const set = new Set<string>()
    tokens.forEach(t => set.add(`${t.x},${t.y}`))
    return set
  }, [tokens])

  const reachable = useMemo(() => {
    if (!playerPosition || !canMove) return new Set<string>()
    const set = new Set<string>()
    for (let dx = -speedSquares; dx <= speedSquares; dx++) {
      for (let dy = -speedSquares; dy <= speedSquares; dy++) {
        if (dx === 0 && dy === 0) continue
        if (Math.max(Math.abs(dx), Math.abs(dy)) > speedSquares) continue
        const x = playerPosition.x + dx
        const y = playerPosition.y + dy
        if (x < tightView.minX || x >= tightView.minX + tightView.width) continue
        if (y < tightView.minY || y >= tightView.minY + tightView.height) continue
        if (occupied.has(`${x},${y}`)) continue
        set.add(`${x},${y}`)
      }
    }
    return set
  }, [playerPosition, speedSquares, canMove, occupied, tightView])

  const cells: React.ReactElement[] = []
  for (let row = 0; row < tightView.height; row++) {
    for (let col = 0; col < tightView.width; col++) {
      const x = tightView.minX + col
      const y = tightView.minY + row
      const key = `${x},${y}`
      const isReachable = reachable.has(key)
      const className = `combat-grid-cell${isReachable ? ' reachable' : ''}${isReachable && withdrawMode ? ' withdraw' : ''}`
      cells.push(
        <rect
          key={key}
          x={col * cellPx}
          y={row * cellPx}
          width={cellPx}
          height={cellPx}
          className={className}
          onClick={isReachable && !busy ? () => onSquareClick(x, y) : undefined}
          style={isReachable && !busy ? { cursor: 'pointer' } : undefined}
        />,
      )
    }
  }

  const tokenEls = tokens.map(t => {
    const col = t.x - tightView.minX
    const row = t.y - tightView.minY
    const cx = col * cellPx + cellPx / 2
    const cy = row * cellPx + cellPx / 2
    const r = Math.max(4, cellPx * 0.35)
    const target = findCreatureHp(targets, t.creatureSheetId)
    const isDown = !!target?.dropped
    const className = `combat-grid-token ${t.isPlayer ? 'player' : 'npc'}${isDown ? ' down' : ''}`
    const hpPart = target ? ` — ${target.hp}/${target.max_hp} HP${isDown ? ' (down)' : ''}` : ''
    const tooltip = `${t.displayLabel} (${t.x}, ${t.y})${hpPart}`
    return (
      <g key={t.id} className={className}>
        {/* SVG <title> as the first child gives browsers the most reliable
            hover-tooltip behavior — keeps the disambiguated label + HP
            visible without occluding the grid. */}
        <title>{tooltip}</title>
        <circle cx={cx} cy={cy} r={r} />
        <text x={cx} y={cy + 1} textAnchor="middle" dominantBaseline="middle" fontSize={Math.max(8, cellPx * 0.4)}>
          {t.isPlayer ? '@' : (t.displayLabel[0] || '?').toUpperCase()}
        </text>
      </g>
    )
  })

  return (
    <div className="combat-grid-wrapper">
      <svg
        className="combat-grid"
        width={tightView.width * cellPx}
        height={tightView.height * cellPx}
        role="img"
        aria-label="Combat grid"
      >
        {cells}
        {tokenEls}
      </svg>
      <div className="combat-grid-controls">
        <button
          type="button"
          className={`withdraw-toggle${withdrawMode ? ' active' : ''}`}
          disabled={!canWithdraw || busy}
          onClick={onWithdrawToggle}
          title="Withdraw — full-round action; the square you leave does NOT provoke. Costs both standard and move."
        >
          {withdrawMode ? '↩ Withdrawing' : '↩ Withdraw'}
        </button>
        <span className="combat-grid-hint">
          {canMove
            ? withdrawMode
              ? <>Withdrawing — click a square to safely leave melee. Costs your full round.</>
              : <>Click a highlighted square to move. Speed {speedSquares} squares ({speedSquares * 5} ft).</>
            : <>Move action spent — click <em>End Turn</em> to refresh.</>}
        </span>
      </div>
    </div>
  )
}

export default CombatGrid
