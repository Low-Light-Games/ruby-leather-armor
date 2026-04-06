/**
 * Pathfinder 1e class skill lists (Core / SRD). Keys must match `PATHFINDER_SKILLS` names.
 *
 * Server mirror (keep identical): app/services/character_stats/class_skills_data.rb
 * (`CharacterStats::ClassSkillsData::LISTS`).
 */
export const CLASS_SKILLS_BY_ID: Record<string, readonly string[]> = {
  barbarian: [
    'Acrobatics', 'Climb', 'Craft', 'Handle Animal', 'Intimidate', 'Knowledge (nature)',
    'Perception', 'Ride', 'Survival', 'Swim',
  ],
  bard: [
    'Acrobatics', 'Appraise', 'Bluff', 'Climb', 'Craft', 'Diplomacy', 'Disguise', 'Escape Artist',
    'Intimidate', 'Knowledge (arcana)', 'Knowledge (dungeoneering)', 'Knowledge (engineering)',
    'Knowledge (geography)', 'Knowledge (history)', 'Knowledge (local)', 'Knowledge (nature)',
    'Knowledge (nobility)', 'Knowledge (planes)', 'Knowledge (religion)', 'Linguistics',
    'Perception', 'Perform', 'Profession', 'Sense Motive', 'Sleight of Hand', 'Spellcraft',
    'Stealth', 'Use Magic Device',
  ],
  cleric: [
    'Appraise', 'Craft', 'Diplomacy', 'Heal', 'Knowledge (arcana)', 'Knowledge (history)',
    'Knowledge (nobility)', 'Knowledge (planes)', 'Knowledge (religion)', 'Linguistics',
    'Profession', 'Sense Motive', 'Spellcraft',
  ],
  druid: [
    'Climb', 'Craft', 'Fly', 'Handle Animal', 'Heal', 'Knowledge (geography)', 'Knowledge (nature)',
    'Perception', 'Profession', 'Ride', 'Spellcraft', 'Survival', 'Swim',
  ],
  fighter: [
    'Climb', 'Craft', 'Handle Animal', 'Intimidate', 'Knowledge (dungeoneering)',
    'Knowledge (engineering)', 'Profession', 'Ride', 'Survival', 'Swim',
  ],
  monk: [
    'Acrobatics', 'Climb', 'Craft', 'Escape Artist', 'Intimidate', 'Knowledge (history)',
    'Knowledge (religion)', 'Perception', 'Perform', 'Profession', 'Ride', 'Stealth', 'Swim',
  ],
  paladin: [
    'Craft', 'Diplomacy', 'Handle Animal', 'Heal', 'Knowledge (nobility)', 'Knowledge (religion)',
    'Profession', 'Ride', 'Sense Motive', 'Spellcraft',
  ],
  ranger: [
    'Climb', 'Craft', 'Handle Animal', 'Heal', 'Intimidate', 'Knowledge (dungeoneering)',
    'Knowledge (geography)', 'Knowledge (nature)', 'Perception', 'Profession', 'Ride', 'Spellcraft',
    'Stealth', 'Survival', 'Swim',
  ],
  rogue: [
    'Acrobatics', 'Appraise', 'Bluff', 'Climb', 'Craft', 'Diplomacy', 'Disable Device', 'Disguise',
    'Escape Artist', 'Intimidate', 'Knowledge (dungeoneering)', 'Knowledge (local)', 'Linguistics',
    'Perception', 'Perform', 'Profession', 'Sense Motive', 'Sleight of Hand', 'Stealth', 'Swim',
    'Use Magic Device',
  ],
  sorcerer: [
    'Appraise', 'Bluff', 'Craft', 'Fly', 'Intimidate', 'Knowledge (arcana)', 'Profession',
    'Spellcraft', 'Use Magic Device',
  ],
  wizard: [
    'Appraise', 'Craft', 'Fly', 'Knowledge (arcana)', 'Knowledge (dungeoneering)',
    'Knowledge (engineering)', 'Knowledge (geography)', 'Knowledge (history)', 'Knowledge (local)',
    'Knowledge (nature)', 'Knowledge (nobility)', 'Knowledge (planes)', 'Knowledge (religion)',
    'Linguistics', 'Profession', 'Spellcraft',
  ],
};

export function isClassSkill(skillName: string, classId: string | null): boolean {
  if (!classId) return false;
  const list = CLASS_SKILLS_BY_ID[classId];
  return list ? list.includes(skillName) : false;
}
