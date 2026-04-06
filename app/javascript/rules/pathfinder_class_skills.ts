/**
 * Pathfinder 1e class skill lists (Core / SRD). Strings must match `PATHFINDER_SKILLS` in
 * pathfinder_skills.ts exactly (including Knowledge (Arcana)-style title case).
 *
 * Server mirror (keep identical): app/services/character_stats/class_skills_data.rb
 * (`CharacterStats::ClassSkillsData::LISTS`).
 */
export const CLASS_SKILLS_BY_ID: Record<string, readonly string[]> = {
  barbarian: [
    'Acrobatics', 'Climb', 'Craft', 'Handle Animal', 'Intimidate', 'Knowledge (Nature)',
    'Perception', 'Ride', 'Survival', 'Swim',
  ],
  bard: [
    'Acrobatics', 'Appraise', 'Bluff', 'Climb', 'Craft', 'Diplomacy', 'Disguise', 'Escape Artist',
    'Intimidate', 'Knowledge (Arcana)', 'Knowledge (Dungeoneering)', 'Knowledge (Engineering)',
    'Knowledge (Geography)', 'Knowledge (History)', 'Knowledge (Local)', 'Knowledge (Nature)',
    'Knowledge (Nobility)', 'Knowledge (Planes)', 'Knowledge (Religion)', 'Linguistics',
    'Perception', 'Perform', 'Profession', 'Sense Motive', 'Sleight of Hand', 'Spellcraft',
    'Stealth', 'Use Magic Device',
  ],
  cleric: [
    'Appraise', 'Craft', 'Diplomacy', 'Heal', 'Knowledge (Arcana)', 'Knowledge (History)',
    'Knowledge (Nobility)', 'Knowledge (Planes)', 'Knowledge (Religion)', 'Linguistics',
    'Profession', 'Sense Motive', 'Spellcraft',
  ],
  druid: [
    'Climb', 'Craft', 'Fly', 'Handle Animal', 'Heal', 'Knowledge (Geography)', 'Knowledge (Nature)',
    'Perception', 'Profession', 'Ride', 'Spellcraft', 'Survival', 'Swim',
  ],
  fighter: [
    'Climb', 'Craft', 'Handle Animal', 'Intimidate', 'Knowledge (Dungeoneering)',
    'Knowledge (Engineering)', 'Profession', 'Ride', 'Survival', 'Swim',
  ],
  monk: [
    'Acrobatics', 'Climb', 'Craft', 'Escape Artist', 'Intimidate', 'Knowledge (History)',
    'Knowledge (Religion)', 'Perception', 'Perform', 'Profession', 'Ride', 'Stealth', 'Swim',
  ],
  paladin: [
    'Craft', 'Diplomacy', 'Handle Animal', 'Heal', 'Knowledge (Nobility)', 'Knowledge (Religion)',
    'Profession', 'Ride', 'Sense Motive', 'Spellcraft',
  ],
  ranger: [
    'Climb', 'Craft', 'Handle Animal', 'Heal', 'Intimidate', 'Knowledge (Dungeoneering)',
    'Knowledge (Geography)', 'Knowledge (Nature)', 'Perception', 'Profession', 'Ride', 'Spellcraft',
    'Stealth', 'Survival', 'Swim',
  ],
  rogue: [
    'Acrobatics', 'Appraise', 'Bluff', 'Climb', 'Craft', 'Diplomacy', 'Disable Device', 'Disguise',
    'Escape Artist', 'Intimidate', 'Knowledge (Dungeoneering)', 'Knowledge (Local)', 'Linguistics',
    'Perception', 'Perform', 'Profession', 'Sense Motive', 'Sleight of Hand', 'Stealth', 'Swim',
    'Use Magic Device',
  ],
  sorcerer: [
    'Appraise', 'Bluff', 'Craft', 'Fly', 'Intimidate', 'Knowledge (Arcana)', 'Profession',
    'Spellcraft', 'Use Magic Device',
  ],
  wizard: [
    'Appraise', 'Craft', 'Fly', 'Knowledge (Arcana)', 'Knowledge (Dungeoneering)',
    'Knowledge (Engineering)', 'Knowledge (Geography)', 'Knowledge (History)', 'Knowledge (Local)',
    'Knowledge (Nature)', 'Knowledge (Nobility)', 'Knowledge (Planes)', 'Knowledge (Religion)',
    'Linguistics', 'Profession', 'Spellcraft',
  ],
};

export function isClassSkill(skillName: string, classId: string | null): boolean {
  if (!classId) return false;
  const list = CLASS_SKILLS_BY_ID[classId];
  return list ? list.includes(skillName) : false;
}
