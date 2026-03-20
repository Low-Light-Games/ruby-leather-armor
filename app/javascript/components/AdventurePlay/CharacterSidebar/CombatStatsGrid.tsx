import type { AdventureSheet, DerivedStats } from '../../../types'
import type { Currency, ItemDefinition } from '../../../rules/pathfinder_items_types'
import { formatMod } from '../../../utils/formatting'
import { formatCurrency } from '../../../rules/pathfinder_items'
import { getUnarmedDamageDice } from '../../../rules/pathfinder_unarmed'
import StatTooltip from '../../ui/StatTooltip'
import type { StatBreakdownLine } from '../../../types'

function hasConditionEntry(breakdown?: StatBreakdownLine[]): boolean {
  return !!breakdown?.some(e => e.type === 'condition')
}

interface CombatStatsGridProps {
  sheet: AdventureSheet
  ds: DerivedStats
  equippedWeapons: { item: ItemDefinition; id: string }[]
  rollFort: () => void
  rollRef: () => void
  rollWill: () => void
  rollWeaponDamage: (itemId: string) => void
  rollUnarmedDamage: () => void
}

const CombatStatsGrid = ({
  sheet, ds, equippedWeapons,
  rollFort, rollRef, rollWill,
  rollWeaponDamage, rollUnarmedDamage,
}: CombatStatsGridProps) => (
  <>
    <div className="combat-stats">
      <div className="combat-stat">
        <span className="stat-label">AC</span>
        <StatTooltip label="AC" total={ds.ac} breakdown={ds.ac_breakdown}>
          <span className={`stat-value${hasConditionEntry(ds.ac_breakdown) ? ' condition-affected' : ''}`}>{ds.ac}</span>
        </StatTooltip>
      </div>
      <div className="combat-stat"><span className="stat-label">Touch AC</span><span className="stat-value">{ds.touch_ac}</span></div>
      <div className="combat-stat"><span className="stat-label">Flat-Foot</span><span className="stat-value">{ds.flat_footed_ac}</span></div>
      <div className="combat-stat"><span className="stat-label">HP</span><span className="stat-value">{sheet.hp} / {ds.max_hp}</span></div>
      <div className="combat-stat"><span className="stat-label">BAB</span><span className="stat-value">{formatMod(ds.bab)}</span></div>
      <div className="combat-stat"><span className="stat-label">CMB</span><span className="stat-value">{formatMod(ds.cmb)}</span></div>
      <div className="combat-stat"><span className="stat-label">CMD</span><span className="stat-value">{ds.cmd}</span></div>
      <div className="combat-stat"><span className="stat-label">Speed</span><span className="stat-value">{ds.speed} ft</span></div>
    </div>

    <div className="saves-row">
      <button className="save-item rollable" onClick={rollFort} title="Roll Fortitude Save">
        <span className="save-label">Fort</span>
        <StatTooltip label="Fortitude" total={formatMod(ds.fort)} breakdown={ds.fort_breakdown}>
          <span className={`save-value${hasConditionEntry(ds.fort_breakdown) ? ' condition-affected' : ''}`}>{formatMod(ds.fort)}</span>
        </StatTooltip>
        <span className="roll-dice-hint">🎲</span>
      </button>
      <button className="save-item rollable" onClick={rollRef} title="Roll Reflex Save">
        <span className="save-label">Ref</span>
        <StatTooltip label="Reflex" total={formatMod(ds.ref)} breakdown={ds.ref_breakdown}>
          <span className={`save-value${hasConditionEntry(ds.ref_breakdown) ? ' condition-affected' : ''}`}>{formatMod(ds.ref)}</span>
        </StatTooltip>
        <span className="roll-dice-hint">🎲</span>
      </button>
      <button className="save-item rollable" onClick={rollWill} title="Roll Will Save">
        <span className="save-label">Will</span>
        <StatTooltip label="Will" total={formatMod(ds.will)} breakdown={ds.will_breakdown}>
          <span className={`save-value${hasConditionEntry(ds.will_breakdown) ? ' condition-affected' : ''}`}>{formatMod(ds.will)}</span>
        </StatTooltip>
        <span className="roll-dice-hint">🎲</span>
      </button>
    </div>

    <div className="damage-tiles">
      {equippedWeapons.length > 0 ? (
        equippedWeapons.map(({ item, id }) => (
          <button key={id} className="damage-tile" onClick={() => rollWeaponDamage(id)}
            title={`Roll ${item.name} Damage`}>
            <span className="damage-tile-label">{item.name}</span>
            <span className="damage-tile-dice">{item.damageDice}</span>
            <span className="roll-dice-hint">🎲</span>
          </button>
        ))
      ) : (
        <button className="damage-tile" onClick={rollUnarmedDamage} title="Roll Unarmed Damage">
          <span className="damage-tile-label">Unarmed</span>
          <span className="damage-tile-dice">{getUnarmedDamageDice(sheet.character_class, sheet.level)}</span>
          <span className="roll-dice-hint">🎲</span>
        </button>
      )}
    </div>

    <div className="adventure-gold">
      <span className="stat-label">Currency</span>
      <span className="stat-value gold">{formatCurrency(sheet.currency as Currency)}</span>
    </div>
  </>
)

export default CombatStatsGrid
