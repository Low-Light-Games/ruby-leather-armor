import { AttributeType } from '../types';

export interface SkillDefinition {
  name: string;
  keyAbility: AttributeType;
  trainedOnly: boolean;
  armorCheckPenalty: boolean;
}

/**
 * Complete list of Pathfinder 1e skills from the Core Rulebook SRD.
 * Each entry maps a skill to its key ability score, whether it can
 * only be used trained, and whether armor check penalties apply.
 */
export const PATHFINDER_SKILLS: SkillDefinition[] = [
  { name: 'Acrobatics',                keyAbility: 'dexterity',     trainedOnly: false, armorCheckPenalty: true  },
  { name: 'Appraise',                  keyAbility: 'intelligence',  trainedOnly: false, armorCheckPenalty: false },
  { name: 'Bluff',                     keyAbility: 'charisma',      trainedOnly: false, armorCheckPenalty: false },
  { name: 'Climb',                     keyAbility: 'strength',      trainedOnly: false, armorCheckPenalty: true  },
  { name: 'Craft',                     keyAbility: 'intelligence',  trainedOnly: false, armorCheckPenalty: false },
  { name: 'Diplomacy',                 keyAbility: 'charisma',      trainedOnly: false, armorCheckPenalty: false },
  { name: 'Disable Device',            keyAbility: 'dexterity',     trainedOnly: true,  armorCheckPenalty: true  },
  { name: 'Disguise',                  keyAbility: 'charisma',      trainedOnly: false, armorCheckPenalty: false },
  { name: 'Escape Artist',             keyAbility: 'dexterity',     trainedOnly: false, armorCheckPenalty: true  },
  { name: 'Fly',                       keyAbility: 'dexterity',     trainedOnly: false, armorCheckPenalty: true  },
  { name: 'Handle Animal',             keyAbility: 'charisma',      trainedOnly: true,  armorCheckPenalty: false },
  { name: 'Heal',                      keyAbility: 'wisdom',        trainedOnly: false, armorCheckPenalty: false },
  { name: 'Intimidate',                keyAbility: 'charisma',      trainedOnly: false, armorCheckPenalty: false },
  { name: 'Knowledge (Arcana)',        keyAbility: 'intelligence',  trainedOnly: true,  armorCheckPenalty: false },
  { name: 'Knowledge (Dungeoneering)', keyAbility: 'intelligence',  trainedOnly: true,  armorCheckPenalty: false },
  { name: 'Knowledge (Engineering)',   keyAbility: 'intelligence',  trainedOnly: true,  armorCheckPenalty: false },
  { name: 'Knowledge (Geography)',     keyAbility: 'intelligence',  trainedOnly: true,  armorCheckPenalty: false },
  { name: 'Knowledge (History)',       keyAbility: 'intelligence',  trainedOnly: true,  armorCheckPenalty: false },
  { name: 'Knowledge (Local)',         keyAbility: 'intelligence',  trainedOnly: true,  armorCheckPenalty: false },
  { name: 'Knowledge (Nature)',        keyAbility: 'intelligence',  trainedOnly: true,  armorCheckPenalty: false },
  { name: 'Knowledge (Nobility)',      keyAbility: 'intelligence',  trainedOnly: true,  armorCheckPenalty: false },
  { name: 'Knowledge (Planes)',        keyAbility: 'intelligence',  trainedOnly: true,  armorCheckPenalty: false },
  { name: 'Knowledge (Religion)',      keyAbility: 'intelligence',  trainedOnly: true,  armorCheckPenalty: false },
  { name: 'Linguistics',               keyAbility: 'intelligence',  trainedOnly: true,  armorCheckPenalty: false },
  { name: 'Perception',                keyAbility: 'wisdom',        trainedOnly: false, armorCheckPenalty: false },
  { name: 'Perform',                   keyAbility: 'charisma',      trainedOnly: false, armorCheckPenalty: false },
  { name: 'Profession',                keyAbility: 'wisdom',        trainedOnly: true,  armorCheckPenalty: false },
  { name: 'Ride',                      keyAbility: 'dexterity',     trainedOnly: false, armorCheckPenalty: true  },
  { name: 'Sense Motive',              keyAbility: 'wisdom',        trainedOnly: false, armorCheckPenalty: false },
  { name: 'Sleight of Hand',           keyAbility: 'dexterity',     trainedOnly: true,  armorCheckPenalty: true  },
  { name: 'Spellcraft',                keyAbility: 'intelligence',  trainedOnly: true,  armorCheckPenalty: false },
  { name: 'Stealth',                   keyAbility: 'dexterity',     trainedOnly: false, armorCheckPenalty: true  },
  { name: 'Survival',                  keyAbility: 'wisdom',        trainedOnly: false, armorCheckPenalty: false },
  { name: 'Swim',                      keyAbility: 'strength',      trainedOnly: false, armorCheckPenalty: true  },
  { name: 'Use Magic Device',          keyAbility: 'charisma',      trainedOnly: true,  armorCheckPenalty: false },
];

/**
 * Calculate the ability modifier for a given ability score.
 * Formula: floor((score − 10) / 2)
 */
export function abilityModifier(score: number): number {
  return Math.floor((score - 10) / 2);
}
