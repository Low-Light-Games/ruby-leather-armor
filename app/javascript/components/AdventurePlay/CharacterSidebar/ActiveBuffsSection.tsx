import React from 'react'
import type { ActiveBuff } from '../../../types'

const TARGET_LABELS: Record<string, string> = {
  ac: 'AC',
  speed: 'Speed',
  saves: 'Saves',
  attack: 'Attack',
  damage: 'Damage',
  strength: 'STR',
  dexterity: 'DEX',
  constitution: 'CON',
  intelligence: 'INT',
  wisdom: 'WIS',
  charisma: 'CHA',
}

function targetLabelFor(target: string): string {
  return TARGET_LABELS[target] ?? target
}

function effectSummaryFor(buff: ActiveBuff): string {
  const sign = buff.value >= 0 ? '+' : ''
  return `${buff.bonus_type} ${sign}${buff.value} -> ${targetLabelFor(buff.target)}`
}

function rowKey(buff: ActiveBuff, index: number): string {
  const exp = buff.expires_at_game_hours ?? '—'
  const metaKeys =
    buff.meta && typeof buff.meta === 'object' ? Object.keys(buff.meta).sort().join(',') : ''
  return [
    buff.source,
    buff.source_type ?? '',
    buff.target,
    buff.bonus_type,
    String(buff.value),
    String(exp),
    buff.duration_label,
    metaKeys,
    String(index),
  ].join('|')
}

interface ActiveBuffsSectionProps {
  buffs: ActiveBuff[]
}

const ActiveBuffsSection: React.FC<ActiveBuffsSectionProps> = ({ buffs }) => {
  if (buffs.length === 0) return null

  return (
    <div className="active-buffs-section">
      <div className="active-buffs-header">
        <h3>Active Buffs</h3>
        <span className="active-buffs-count">{buffs.length}</span>
      </div>
      <div className="active-buffs-list">
        {buffs.map((buff, index) => (
          <div
            key={rowKey(buff, index)}
            className="active-buff-row"
          >
            <div className="active-buff-main">
              <span className="active-buff-source">{buff.source}</span>
              <span className="active-buff-effect">{effectSummaryFor(buff)}</span>
            </div>
            <span className="active-buff-duration">{buff.duration_label}</span>
          </div>
        ))}
      </div>
    </div>
  )
}

export default ActiveBuffsSection
