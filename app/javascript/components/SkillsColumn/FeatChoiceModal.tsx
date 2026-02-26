import React, { useMemo } from 'react';
import { PATHFINDER_SKILLS } from '../../rules/pathfinder_skills';
import { parseFeatEntry } from '../../rules/pathfinder_feats';
import type { FeatDefinition } from '../../rules/pathfinder_feats';

const SKILL_CHOICES = PATHFINDER_SKILLS.map(s => s.name);

const WEAPON_CHOICES = [
  'Bastard Sword', 'Battle Axe', 'Club', 'Composite Longbow', 'Composite Shortbow',
  'Dagger', 'Dart', 'Dwarven Waraxe', 'Elven Curve Blade', 'Falchion',
  'Flail', 'Glaive', 'Gnome Hooked Hammer', 'Greataxe', 'Greatclub',
  'Greatsword', 'Guisarme', 'Halberd', 'Handaxe', 'Hand Crossbow',
  'Heavy Crossbow', 'Heavy Flail', 'Heavy Mace', 'Heavy Pick', 'Heavy Shield',
  'Javelin', 'Kama', 'Kukri', 'Lance', 'Light Crossbow',
  'Light Flail', 'Light Hammer', 'Light Mace', 'Light Pick', 'Light Shield',
  'Longbow', 'Longsword', 'Longspear', 'Morningstar', 'Net',
  'Nunchaku', 'Orc Double Axe', 'Quarterstaff', 'Ranseur', 'Rapier',
  'Sai', 'Scimitar', 'Scythe', 'Short Sword', 'Shortbow',
  'Shortspear', 'Shuriken', 'Siangham', 'Sickle', 'Sling',
  'Spear', 'Spiked Chain', 'Starknife', 'Trident', 'Unarmed Strike',
  'War Hammer', 'Whip',
];

const SPELL_SCHOOL_CHOICES = [
  'Abjuration', 'Conjuration', 'Divination', 'Enchantment',
  'Evocation', 'Illusion', 'Necromancy', 'Transmutation',
];

interface FeatChoiceModalProps {
  feat: FeatDefinition;
  choiceType: 'skill' | 'weapon' | 'school';
  search: string;
  onSearchChange: (val: string) => void;
  onConfirm: (choice: string) => void;
  onCancel: () => void;
  alreadySelected: string[];
}

const FeatChoiceModal: React.FC<FeatChoiceModalProps> = ({
  feat,
  choiceType,
  search,
  onSearchChange,
  onConfirm,
  onCancel,
  alreadySelected,
}) => {
  const allChoices = choiceType === 'skill' ? SKILL_CHOICES
    : choiceType === 'weapon' ? WEAPON_CHOICES
    : SPELL_SCHOOL_CHOICES;

  // Choices already taken for this repeatable feat
  const takenChoices = useMemo(() => {
    const taken = new Set<string>();
    for (const entry of alreadySelected) {
      const parsed = parseFeatEntry(entry);
      if (parsed.featId === feat.id && parsed.choice) {
        taken.add(parsed.choice);
      }
    }
    return taken;
  }, [alreadySelected, feat.id]);

  const filtered = useMemo(() => {
    const term = search.toLowerCase().trim();
    return allChoices
      .filter(c => !takenChoices.has(c))
      .filter(c => !term || c.toLowerCase().includes(term));
  }, [allChoices, takenChoices, search]);

  const title = choiceType === 'skill' ? 'Choose a Skill'
    : choiceType === 'weapon' ? 'Choose a Weapon'
    : 'Choose a Spell School';

  return (
    <div className="feat-choice-overlay" onClick={onCancel}>
      <div className="feat-choice-modal" onClick={e => e.stopPropagation()}>
        <div className="fcm-header">
          <h3>{feat.name}</h3>
          <button className="fcm-close" onClick={onCancel}>&times;</button>
        </div>
        <p className="fcm-subtitle">{title}</p>
        <p className="fcm-description">{feat.summary}</p>
        <input
          type="text"
          className="fcm-search"
          placeholder={`Search ${choiceType}s…`}
          value={search}
          onChange={e => onSearchChange(e.target.value)}
          autoFocus
        />
        <ul className="fcm-list">
          {filtered.map(choice => (
            <li key={choice} className="fcm-item" onClick={() => onConfirm(choice)}>
              {choice}
            </li>
          ))}
          {filtered.length === 0 && (
            <li className="fcm-empty">No matching {choiceType}s found.</li>
          )}
        </ul>
      </div>
    </div>
  );
};

export default FeatChoiceModal;
