import { useMemo } from 'react'
import type { CombatTarget } from '../../../services/combatActionService'
import './CombatGrid.scss'
import {
  COMBAT_GRID_DEFAULT_CELL_PX,
  COMBAT_GRID_DEFAULT_VIEWPORT_HEIGHT,
  COMBAT_GRID_DEFAULT_VIEWPORT_WIDTH,
  COMBAT_GRID_MAX_TOTAL_PX,
  COMBAT_GRID_MIN_CELL_PX,
  COMBAT_GRID_MOBILE_VIEW_SQUARES,
  COMBAT_GRID_VIEWPORT_PADDING_FLOOR,
} from './constants'
import type { CombatGridProps, ResolvedToken, ViewportRect } from './types'

function readViewport(viewport: Record<string, unknown>): ViewportRect {
  const minX = typeof viewport.min_x === 'number' ? viewport.min_x : 0
  const minY = typeof viewport.min_y === 'number' ? viewport.min_y : 0
  const width = typeof viewport.width === 'number' && viewport.width > 0
    ? viewport.width : COMBAT_GRID_DEFAULT_VIEWPORT_WIDTH
  const height = typeof viewport.height === 'number' && viewport.height > 0
    ? viewport.height : COMBAT_GRID_DEFAULT_VIEWPORT_HEIGHT
  return { minX, minY, width, height }
}

function parseRawToken(id: string, raw: Record<string, unknown>): Omit<ResolvedToken, 'displayLabel'> | null {
  const x = typeof raw.x === 'number' ? raw.x : null
  const y = typeof raw.y === 'number' ? raw.y : null
  if (x == null || y == null) return null
  return {
    id,
    label: typeof raw.label === 'string' ? raw.label : id,
    x,
    y,
    type: typeof raw.type === 'string' ? raw.type : 'npc',
    creatureSheetId: typeof raw.actor_sheet_id === 'number' ? raw.actor_sheet_id : null,
    isPlayer: id === 'player',
  }
}

// Disambiguates same-name NPCs with a #N suffix ("Goblin" → "Goblin #1",
// "Goblin #2") so the tooltip can tell two of the same kind apart.
function withDisambiguatedLabels(tokens: Omit<ResolvedToken, 'displayLabel'>[]): ResolvedToken[] {
  const labelCounts = new Map<string, number>()
  tokens.forEach(t => {
    if (t.isPlayer) return
    labelCounts.set(t.label, (labelCounts.get(t.label) || 0) + 1)
  })
  const labelSeen = new Map<string, number>()
  return tokens.map(t => {
    if (t.isPlayer || (labelCounts.get(t.label) || 0) <= 1) {
      return { ...t, displayLabel: t.label }
    }
    const seen = (labelSeen.get(t.label) || 0) + 1
    labelSeen.set(t.label, seen)
    return { ...t, displayLabel: `${t.label} #${seen}` }
  })
}

function readTokens(tokens: Record<string, Record<string, unknown>>): ResolvedToken[] {
  const intermediate: Omit<ResolvedToken, 'displayLabel'>[] = []
  for (const [id, raw] of Object.entries(tokens)) {
    if (!raw || typeof raw !== 'object') continue
    const parsed = parseRawToken(id, raw)
    if (parsed) intermediate.push(parsed)
  }
  return withDisambiguatedLabels(intermediate)
}

function findCreatureHp(targets: CombatTarget[] | undefined, creatureSheetId: number | null) {
  if (!targets || creatureSheetId == null) return null
  return targets.find(t => t.actor_sheet_id === creatureSheetId) || null
}

function tightViewportFor(tokens: ResolvedToken[], viewport: ViewportRect, speedSquares: number): ViewportRect {
  if (tokens.length === 0) return viewport
  const xs = tokens.map(t => t.x)
  const ys = tokens.map(t => t.y)
  const pad = Math.max(speedSquares, COMBAT_GRID_VIEWPORT_PADDING_FLOOR)
  const minX = Math.min(...xs) - pad
  const maxX = Math.max(...xs) + pad
  const minY = Math.min(...ys) - pad
  const maxY = Math.max(...ys) + pad
  return { minX, minY, width: maxX - minX + 1, height: maxY - minY + 1 }
}

function cellPxFor(view: ViewportRect): number {
  const widest = Math.max(view.width, view.height)
  if (widest <= 0) return COMBAT_GRID_DEFAULT_CELL_PX
  return Math.max(COMBAT_GRID_MIN_CELL_PX, Math.min(COMBAT_GRID_DEFAULT_CELL_PX, Math.floor(COMBAT_GRID_MAX_TOTAL_PX / widest)))
}

// Returns the SVG viewBox string for mobile: a MOBILE_VIEW_SQUARES×MOBILE_VIEW_SQUARES
// window centred on the player. The SVG is scaled to fill its container via CSS
// width:100%, so fewer squares = larger tiles (~46px on a standard phone).
function mobileViewBox(
  playerPosition: { x: number; y: number } | null,
  tightView: ViewportRect,
  cellPx: number,
): string {
  const size = Math.min(COMBAT_GRID_MOBILE_VIEW_SQUARES, tightView.width, tightView.height)
  const half = Math.floor(size / 2)

  const centerCol = playerPosition != null
    ? playerPosition.x - tightView.minX
    : Math.floor(tightView.width / 2)
  const centerRow = playerPosition != null
    ? playerPosition.y - tightView.minY
    : Math.floor(tightView.height / 2)

  const startCol = Math.max(0, Math.min(centerCol - half, tightView.width - size))
  const startRow = Math.max(0, Math.min(centerRow - half, tightView.height - size))

  return `${startCol * cellPx} ${startRow * cellPx} ${size * cellPx} ${size * cellPx}`
}

function reachableSquaresFrom(
  playerPosition: { x: number; y: number } | null, canMove: boolean, speedSquares: number,
  occupied: Set<string>, view: ViewportRect,
): Set<string> {
  if (!playerPosition || !canMove) return new Set<string>()
  const set = new Set<string>()
  for (let dx = -speedSquares; dx <= speedSquares; dx++) {
    for (let dy = -speedSquares; dy <= speedSquares; dy++) {
      if (dx === 0 && dy === 0) continue
      if (Math.max(Math.abs(dx), Math.abs(dy)) > speedSquares) continue
      const x = playerPosition.x + dx
      const y = playerPosition.y + dy
      if (x < view.minX || x >= view.minX + view.width) continue
      if (y < view.minY || y >= view.minY + view.height) continue
      if (occupied.has(`${x},${y}`)) continue
      set.add(`${x},${y}`)
    }
  }
  return set
}

const isMobile = typeof window !== 'undefined' && window.matchMedia('(max-width: 768px)').matches

export const CombatGrid = ({
  battlefield, playerPosition, speedSquares, canMove, canWithdraw, withdrawMode,
  onWithdrawToggle, onSquareClick, busy, targets,
}: CombatGridProps) => {
  const viewport = useMemo(() => readViewport(battlefield.viewport), [battlefield.viewport])
  const tokens = useMemo(() => readTokens(battlefield.tokens), [battlefield.tokens])

  const tightView = useMemo(() => tightViewportFor(tokens, viewport, speedSquares), [tokens, speedSquares, viewport])
  const cellPx = useMemo(() => cellPxFor(tightView), [tightView])
  const svgViewBox = useMemo(
    () => isMobile
      ? mobileViewBox(playerPosition, tightView, cellPx)
      : `0 0 ${tightView.width * cellPx} ${tightView.height * cellPx}`,
    [playerPosition, tightView, cellPx],
  )
  const occupied = useMemo(() => {
    const set = new Set<string>()
    tokens.forEach(t => set.add(`${t.x},${t.y}`))
    return set
  }, [tokens])
  const reachable = useMemo(
    () => reachableSquaresFrom(playerPosition, canMove, speedSquares, occupied, tightView),
    [playerPosition, speedSquares, canMove, occupied, tightView],
  )

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
        viewBox={svgViewBox}
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
