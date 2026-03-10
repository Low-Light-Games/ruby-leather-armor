import { Accordion } from '../../ui/Accordion'
import type { AdventureSheet } from '../../../types'
import type { SpellDefinition } from '../../../rules/pathfinder_spells_types'
import type { SpellbookSearchResult } from '../hooks/useSpellbook'
import { getSpellById, getCastingStyle } from '../../../rules/pathfinder_spells'
import { spellHasDamage } from '../../../rules/damage'
import { getSpellLevelForClass } from './spellUtils'

interface SpellsSectionProps {
  sheet: AdventureSheet
  isOpen: boolean
  onToggle: () => void
  rollSpellDamage: (spellId: string) => void
  spellbookSearch: string
  setSpellbookSearch: (v: string) => void
  spellbookSaving: boolean
  spellbookSearchResults: SpellbookSearchResult[]
  addSpellToSpellbook: (spell: SpellDefinition) => void
}

const SpellsSection = ({
  sheet, isOpen, onToggle,
  rollSpellDamage,
  spellbookSearch, setSpellbookSearch, spellbookSaving,
  spellbookSearchResults, addSpellToSpellbook,
}: SpellsSectionProps) => {
  const castStyle = getCastingStyle(sheet.character_class)

  const spellIds: string[] = (() => {
    if (castStyle === 'spontaneous') return sheet.details?.knownSpells || sheet.details?.spells || []
    if (castStyle === 'spellbook') return sheet.details?.spellbook || sheet.details?.spells || []
    return sheet.details?.spells || []
  })()

  const spellSectionLabel = castStyle === 'spellbook' ? 'Spellbook'
    : castStyle === 'spontaneous' ? 'Known Spells'
    : 'Spells'

  return (
    <Accordion
      title={`${spellSectionLabel} (${spellIds.length})`}
      isOpen={isOpen}
      onToggle={onToggle}
    >
      {castStyle === 'prepared_list' && (
        <p className="empty-hint" style={{ fontStyle: 'italic' }}>
          Your class knows all spells. Daily preparation coming soon.
        </p>
      )}

      <div className="feats-spells-list">
        {spellIds.length === 0 ? (
          <p className="empty-hint">
            {castStyle === 'spellbook' ? 'Spellbook is empty.' :
             castStyle === 'spontaneous' ? 'No known spells.' :
             'No spells selected.'}
          </p>
        ) : (
          spellIds.map(spellId => {
            const spell = getSpellById(spellId)
            if (!spell) return null
            const lvl = getSpellLevelForClass(spell, sheet.character_class)
            const hasDmg = spellHasDamage(spell)
            return (
              <div key={spell.id} className="fs-item" title={spell.summary}>
                <span className="spell-lvl-badge">{lvl}</span>
                <span className="fs-name">{spell.name}</span>
                <span className="fs-tag school-tag">{spell.school}</span>
                {hasDmg && (
                  <button
                    className="roll-dice-btn spell-dmg"
                    onClick={() => rollSpellDamage(spell.id)}
                    title={`Roll ${spell.name} Damage`}
                    aria-label={`Roll ${spell.name} Damage`}
                  >
                    🎲
                  </button>
                )}
              </div>
            )
          })
        )}
      </div>

      {castStyle === 'spellbook' && (
        <div className="spellbook-add-section">
          <p className="spellbook-add-label">Add spell to spellbook:</p>
          <input
            type="text"
            className="spellbook-search-input"
            placeholder="Search spells to add…"
            value={spellbookSearch}
            onChange={e => setSpellbookSearch(e.target.value)}
            disabled={spellbookSaving}
          />
          {spellbookSearchResults.length > 0 && (
            <ul className="spellbook-dropdown">
              {spellbookSearchResults.map(({ spell, hasSlot }) => {
                const lvl = getSpellLevelForClass(spell, sheet.character_class)
                return (
                  <li
                    key={spell.id}
                    className={`spellbook-option ${!hasSlot ? 'slot-full' : ''}`}
                    onClick={() => hasSlot && addSpellToSpellbook(spell)}
                  >
                    <span className="spell-lvl-badge small">{lvl}</span>
                    <span className="option-name">{spell.name}</span>
                    <span className="fs-tag school-tag">{spell.school}</span>
                    {!hasSlot && <span className="slot-full-hint">slots full</span>}
                  </li>
                )
              })}
            </ul>
          )}
        </div>
      )}
    </Accordion>
  )
}

export default SpellsSection
