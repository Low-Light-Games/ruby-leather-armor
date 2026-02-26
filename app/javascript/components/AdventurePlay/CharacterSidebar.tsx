import React, { useState } from 'react';
import { Accordion } from '../ui/Accordion';
import type { AdventureSheet, AttributeType, DerivedStats } from '../../types';
import type { Currency } from '../../rules/pathfinder_items_types';
import type { SpellDefinition } from '../../rules/pathfinder_spells_types';
import type { SpellbookSearchResult } from './hooks/useSpellbook';
import { formatMod, ABILITY_ABBR, ATTRIBUTE_ORDER } from '../../utils/formatting';
import { formatCurrency } from '../../rules/pathfinder_items';
import { getFeatById, featDisplayName } from '../../rules/pathfinder_feats';
import { getSpellById, getCastingStyle } from '../../rules/pathfinder_spells';

interface CharacterSidebarProps {
  sheet: AdventureSheet;
  ds: DerivedStats;
  // Roll handlers
  rollFort: () => void;
  rollRef: () => void;
  rollWill: () => void;
  rollMeleeAttack: () => void;
  rollRangedAttack: () => void;
  rollInitiative: () => void;
  rollAbility: (attr: AttributeType) => void;
  rollSkill: (skillName: string, total: number) => void;
  // Spellbook
  spellbookSearch: string;
  setSpellbookSearch: (v: string) => void;
  spellbookSaving: boolean;
  spellbookSearchResults: SpellbookSearchResult[];
  addSpellToSpellbook: (spell: SpellDefinition) => void;
}

export const CharacterSidebar: React.FC<CharacterSidebarProps> = ({
  sheet,
  ds,
  rollFort,
  rollRef,
  rollWill,
  rollMeleeAttack,
  rollRangedAttack,
  rollInitiative,
  rollAbility,
  rollSkill,
  spellbookSearch,
  setSpellbookSearch,
  spellbookSaving,
  spellbookSearchResults,
  addSpellToSpellbook,
}) => {
  const [openSections, setOpenSections] = useState<Record<string, boolean>>({
    attributes: true,
    skills: false,
    feats: false,
    spells: false,
  });
  const toggleSection = (section: string) =>
    setOpenSections(prev => ({ ...prev, [section]: !prev[section] }));

  const feats = sheet.details?.feats || [];
  const castStyle = getCastingStyle(sheet.character_class);

  const spellIds: string[] = (() => {
    if (castStyle === 'spontaneous') return sheet.details?.knownSpells || sheet.details?.spells || [];
    if (castStyle === 'spellbook') return sheet.details?.spellbook || sheet.details?.spells || [];
    return sheet.details?.spells || [];
  })();

  const spellSectionLabel = castStyle === 'spellbook' ? 'Spellbook'
    : castStyle === 'spontaneous' ? 'Known Spells'
    : 'Spells';

  return (
    <div className="adventure-column character-column">
      <h2>{sheet.name}</h2>
      {(sheet.race || sheet.character_class) && (
        <p className="char-subtitle">
          {[sheet.race, sheet.character_class].filter(Boolean).join(' ')}
          {sheet.level > 1 && ` (Lv ${sheet.level})`}
        </p>
      )}

      {/* Always-visible combat stats */}
      <div className="combat-stats">
        <div className="combat-stat">
          <span className="stat-label">AC</span>
          <span className="stat-value">{ds.ac}</span>
        </div>
        <div className="combat-stat">
          <span className="stat-label">Touch AC</span>
          <span className="stat-value">{ds.touch_ac}</span>
        </div>
        <div className="combat-stat">
          <span className="stat-label">Flat-Foot</span>
          <span className="stat-value">{ds.flat_footed_ac}</span>
        </div>
        <div className="combat-stat">
          <span className="stat-label">HP</span>
          <span className="stat-value">{sheet.hp} / {ds.max_hp}</span>
        </div>
        <div className="combat-stat">
          <span className="stat-label">BAB</span>
          <span className="stat-value">{formatMod(ds.bab)}</span>
        </div>
        <div className="combat-stat">
          <span className="stat-label">CMB</span>
          <span className="stat-value">{formatMod(ds.cmb)}</span>
        </div>
        <div className="combat-stat">
          <span className="stat-label">CMD</span>
          <span className="stat-value">{ds.cmd}</span>
        </div>
        <div className="combat-stat">
          <span className="stat-label">Speed</span>
          <span className="stat-value">{ds.speed} ft</span>
        </div>
      </div>

      <div className="saves-row">
        <button className="save-item rollable" onClick={rollFort} title="Roll Fortitude Save">
          <span className="save-label">Fort</span>
          <span className="save-value">{formatMod(ds.fort)}</span>
          <span className="roll-dice-hint">🎲</span>
        </button>
        <button className="save-item rollable" onClick={rollRef} title="Roll Reflex Save">
          <span className="save-label">Ref</span>
          <span className="save-value">{formatMod(ds.ref)}</span>
          <span className="roll-dice-hint">🎲</span>
        </button>
        <button className="save-item rollable" onClick={rollWill} title="Roll Will Save">
          <span className="save-label">Will</span>
          <span className="save-value">{formatMod(ds.will)}</span>
          <span className="roll-dice-hint">🎲</span>
        </button>
      </div>

      <div className="adventure-gold">
        <span className="stat-label">Currency</span>
        <span className="stat-value gold">{formatCurrency(sheet.currency as Currency)}</span>
      </div>

      {/* Stacked collapsible sections */}
      <div className="collapsible-sections">
        <Accordion
          title="Attributes"
          isOpen={openSections.attributes}
          onToggle={() => toggleSection('attributes')}
        >
          <div className="attributes-list">
            {ATTRIBUTE_ORDER.map(attr => {
              const base = sheet[attr];
              const final = ds.final_scores[attr] ?? base;
              const racial = final - base;
              const mod = ds.mods[attr] ?? 0;
              return (
                <div key={attr} className="attribute-item">
                  <span className="attr-label">{ABILITY_ABBR[attr]}</span>
                  <span className="attr-score">
                    {base}
                    {racial !== 0 && (
                      <span className={`racial ${racial > 0 ? 'pos' : 'neg'}`}>
                        {racial > 0 ? '+' : ''}{racial}
                      </span>
                    )}
                    {' = '}
                    <strong>{final}</strong>
                  </span>
                  <span className="attr-mod">{formatMod(mod)}</span>
                  <button
                    className="roll-dice-btn"
                    onClick={() => rollAbility(attr)}
                    title={`Roll ${ABILITY_ABBR[attr]} Check`}
                    aria-label={`Roll ${ABILITY_ABBR[attr]} Check`}
                  >
                    🎲
                  </button>
                </div>
              );
            })}
          </div>
        </Accordion>

        <Accordion
          title="Skills"
          isOpen={openSections.skills}
          onToggle={() => toggleSection('skills')}
        >
          <div className="skills-list-adventure">
            {ds.skills.map(skill => (
              <div
                key={skill.name}
                className={`skill-row ${skill.trained_only ? 'trained-only' : ''}`}
              >
                <span className="skill-name">
                  {skill.name}
                  {skill.trained_only && <span className="badge-t">T</span>}
                </span>
                <span className={`skill-mod ${skill.total >= 0 ? 'positive' : 'negative'}`}>
                  {formatMod(skill.total)}
                </span>
                <button
                  className="roll-dice-btn"
                  onClick={() => rollSkill(skill.name, skill.total)}
                  title={`Roll ${skill.name} Check`}
                  aria-label={`Roll ${skill.name} Check`}
                >
                  🎲
                </button>
              </div>
            ))}
          </div>
        </Accordion>

        <Accordion
          title={`Feats (${feats.length})`}
          isOpen={openSections.feats}
          onToggle={() => toggleSection('feats')}
        >
          <div className="feats-spells-list">
            {feats.length === 0 ? (
              <p className="empty-hint">No feats selected.</p>
            ) : (
              feats.map(entry => {
                const feat = getFeatById(entry);
                if (!feat) return null;
                const displayName = featDisplayName(entry);
                return (
                  <div key={entry} className="fs-item" title={feat.summary}>
                    <span className="fs-name">{displayName}</span>
                    <span className={`fs-tag cat-${feat.category}`}>{feat.category}</span>
                  </div>
                );
              })
            )}
          </div>
        </Accordion>

        <Accordion
          title={`${spellSectionLabel} (${spellIds.length})`}
          isOpen={openSections.spells}
          onToggle={() => toggleSection('spells')}
        >
          {/* Prepared full-list notice */}
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
                const spell = getSpellById(spellId);
                if (!spell) return null;
                const lvl = sheet.character_class
                  ? spell.classLevels[sheet.character_class.toLowerCase()]
                  : Object.values(spell.classLevels)[0];
                return (
                  <div key={spell.id} className="fs-item" title={spell.summary}>
                    <span className="spell-lvl-badge">{lvl ?? '?'}</span>
                    <span className="fs-name">{spell.name}</span>
                    <span className="fs-tag school-tag">{spell.school}</span>
                  </div>
                );
              })
            )}
          </div>

          {/* Spellbook editing (wizard only during adventure) */}
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
                    const lvl = sheet.character_class
                      ? spell.classLevels[sheet.character_class.toLowerCase()]
                      : '?';
                    return (
                      <li
                        key={spell.id}
                        className={`spellbook-option ${!hasSlot ? 'slot-full' : ''}`}
                        onClick={() => hasSlot && addSpellToSpellbook(spell)}
                      >
                        <span className="spell-lvl-badge small">{lvl ?? '?'}</span>
                        <span className="option-name">{spell.name}</span>
                        <span className="fs-tag school-tag">{spell.school}</span>
                        {!hasSlot && <span className="slot-full-hint">slots full</span>}
                      </li>
                    );
                  })}
                </ul>
              )}
            </div>
          )}
        </Accordion>
      </div>

      {/* Roll buttons */}
      <div className="roll-buttons">
        <h3>Actions</h3>
        <button className="roll-btn attack" onClick={rollMeleeAttack}>⚔️ Melee Attack</button>
        <button className="roll-btn ranged" onClick={rollRangedAttack}>🏹 Ranged Attack</button>
        <button className="roll-btn initiative" onClick={rollInitiative}>⏱️ Roll Initiative</button>
      </div>
    </div>
  );
};
