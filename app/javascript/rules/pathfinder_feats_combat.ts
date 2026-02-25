/**
 * Pathfinder 1e Core Rulebook — Combat Feats.
 * All content is Open Game Content — mechanical rules only.
 */

import { FeatDefinition } from './pathfinder_feats_types';

export const COMBAT_FEATS: FeatDefinition[] = [
  // ─── A ─────────────────────────────────────────────────────

  {
    id: 'arcane_armor_mastery',
    name: 'Arcane Armor Mastery',
    category: 'combat',
    prerequisites: [
      { type: 'feat', feat: 'arcane_armor_training' },
      { type: 'proficiency', weapon: 'medium armor' },
      { type: 'caster_level', minimum: 7 },
    ],
    effects: [
      { type: 'reduce_arcane_failure', reduction: 20, armorCategory: 'medium or heavy' },
    ],
    repeatable: false,
    summary: 'Reduce arcane spell failure from armor by an additional 20%.',
  },
  {
    id: 'arcane_armor_training',
    name: 'Arcane Armor Training',
    category: 'combat',
    prerequisites: [
      { type: 'proficiency', weapon: 'light armor' },
      { type: 'caster_level', minimum: 3 },
    ],
    effects: [
      { type: 'reduce_arcane_failure', reduction: 10, armorCategory: 'light' },
    ],
    repeatable: false,
    summary: 'As a swift action, reduce arcane spell failure from armor by 10% for 1 round.',
  },
  {
    id: 'arcane_strike',
    name: 'Arcane Strike',
    category: 'combat',
    prerequisites: [
      { type: 'class_feature', feature: 'ability to cast arcane spells' },
    ],
    effects: [
      { type: 'action', actionType: 'swift', name: 'Arcane Strike', effect: 'Weapons gain +1 damage (+1 per 5 CL, max +5) and count as magic for overcoming DR. Lasts 1 round.' },
    ],
    repeatable: false,
    summary: 'Swift action to add CL-based bonus damage to weapons and bypass magic DR.',
  },

  // ─── B ─────────────────────────────────────────────────────

  {
    id: 'bleeding_critical',
    name: 'Bleeding Critical',
    category: 'combat',
    prerequisites: [
      { type: 'feat', feat: 'critical_focus' },
      { type: 'bab', minimum: 11 },
    ],
    effects: [
      { type: 'on_critical', effect: 'Target takes 2d6 bleed damage per round.' },
    ],
    repeatable: false,
    summary: 'On confirmed critical, target takes 2d6 bleed damage each round.',
  },
  {
    id: 'blind_fight',
    name: 'Blind-Fight',
    category: 'combat',
    prerequisites: [],
    effects: [
      { type: 'concealment_reroll', description: 'Reroll miss chance from concealment once per attack. Invisible attackers get no bonus to hit you in melee. Not flat-footed against unseen melee attackers.' },
    ],
    repeatable: false,
    summary: 'Reroll concealment miss chance. Not flat-footed vs invisible melee attackers.',
  },
  {
    id: 'blinding_critical',
    name: 'Blinding Critical',
    category: 'combat',
    prerequisites: [
      { type: 'feat', feat: 'critical_focus' },
      { type: 'bab', minimum: 15 },
    ],
    effects: [
      { type: 'on_critical', effect: 'Target is permanently blinded.', save: { saveType: 'fort', dc: '10 + BAB' } },
    ],
    repeatable: false,
    summary: 'On confirmed critical, target is permanently blinded (Fort negates).',
  },

  // ─── C ─────────────────────────────────────────────────────

  {
    id: 'catch_off_guard',
    name: 'Catch Off-Guard',
    category: 'combat',
    prerequisites: [],
    effects: [
      { type: 'negate_penalty', penalty: 'improvised_melee_weapons', description: 'No penalty for using improvised melee weapons.' },
      { type: 'special', description: 'Unarmed opponents are flat-footed against your improvised weapon attacks.' },
    ],
    repeatable: false,
    summary: 'No improvised melee penalty. Unarmed foes flat-footed to your improvised attacks.',
  },
  {
    id: 'channel_smite',
    name: 'Channel Smite',
    category: 'combat',
    prerequisites: [
      { type: 'class_feature', feature: 'channel energy' },
    ],
    effects: [
      { type: 'action', actionType: 'swift', name: 'Channel Smite', effect: 'Channel energy through melee attack. On hit, deal channel energy damage (Will save for half). On miss, channel energy is wasted.' },
    ],
    repeatable: false,
    summary: 'Channel energy through a melee weapon strike as a swift action.',
  },
  {
    id: 'cleave',
    name: 'Cleave',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'strength', minimum: 13 },
      { type: 'feat', feat: 'power_attack' },
      { type: 'bab', minimum: 1 },
    ],
    effects: [
      { type: 'action', actionType: 'standard', name: 'Cleave', effect: 'On melee hit, make additional attack against adjacent foe at same bonus. Take -2 to AC until next turn.' },
    ],
    repeatable: false,
    summary: 'Standard action: on melee hit, one extra attack vs adjacent foe at -2 AC.',
  },
  {
    id: 'combat_expertise',
    name: 'Combat Expertise',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'intelligence', minimum: 13 },
    ],
    effects: [
      { type: 'attack_ac_trade', attackPenalty: -1, acBonus: 1, acBonusType: 'dodge', scalingPerBAB: 4 },
    ],
    repeatable: false,
    summary: 'Trade attack bonus for dodge AC. -1 attack/+1 AC, scaling every 4 BAB.',
  },
  {
    id: 'combat_reflexes',
    name: 'Combat Reflexes',
    category: 'combat',
    prerequisites: [],
    effects: [
      { type: 'extra_aoo', perRound: 'dex_mod' },
      { type: 'special', description: 'May make AoOs while flat-footed.' },
    ],
    repeatable: false,
    summary: 'Additional AoOs per round equal to DEX modifier. May AoO while flat-footed.',
  },
  {
    id: 'critical_focus',
    name: 'Critical Focus',
    category: 'combat',
    prerequisites: [
      { type: 'bab', minimum: 9 },
    ],
    effects: [
      { type: 'bonus', target: 'critical_confirm', bonus: 4 },
    ],
    repeatable: false,
    summary: '+4 bonus on rolls to confirm critical hits.',
  },
  {
    id: 'critical_mastery',
    name: 'Critical Mastery',
    category: 'combat',
    prerequisites: [
      { type: 'feat', feat: 'critical_focus' },
      { type: 'class_level', classId: 'fighter', level: 14 },
    ],
    effects: [
      { type: 'special', description: 'Apply two critical feat effects simultaneously on a confirmed critical hit.' },
    ],
    repeatable: false,
    summary: 'Apply two critical feat effects on a single confirmed critical.',
  },

  // ─── D ─────────────────────────────────────────────────────

  {
    id: 'dazzling_display',
    name: 'Dazzling Display',
    category: 'combat',
    prerequisites: [
      { type: 'feat', feat: 'weapon_focus' },
    ],
    effects: [
      { type: 'action', actionType: 'full_round', name: 'Dazzling Display', effect: 'Intimidate check to demoralize all foes within 30 ft who can see your weapon display.' },
    ],
    repeatable: false,
    summary: 'Full-round action: Intimidate all visible foes within 30 ft.',
  },
  {
    id: 'deadly_aim',
    name: 'Deadly Aim',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'dexterity', minimum: 13 },
      { type: 'bab', minimum: 1 },
    ],
    effects: [
      { type: 'attack_damage_trade', attackPenalty: -1, damageBonus: 2, scalingPerBAB: 4 },
    ],
    repeatable: false,
    summary: 'Trade ranged attack bonus for damage. -1 attack/+2 damage, scaling every 4 BAB.',
  },
  {
    id: 'deafening_critical',
    name: 'Deafening Critical',
    category: 'combat',
    prerequisites: [
      { type: 'feat', feat: 'critical_focus' },
      { type: 'bab', minimum: 13 },
    ],
    effects: [
      { type: 'on_critical', effect: 'Target is permanently deafened.', save: { saveType: 'fort', dc: '10 + BAB' } },
    ],
    repeatable: false,
    summary: 'On confirmed critical, target is permanently deafened (Fort negates).',
  },
  {
    id: 'deflect_arrows',
    name: 'Deflect Arrows',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'dexterity', minimum: 13 },
      { type: 'feat', feat: 'improved_unarmed_strike' },
    ],
    effects: [
      { type: 'deflect', target: 'one ranged attack per round', usesPerRound: 1 },
    ],
    repeatable: false,
    summary: 'Deflect one ranged attack per round when you have a free hand.',
  },
  {
    id: 'disruptive',
    name: 'Disruptive',
    category: 'combat',
    prerequisites: [
      { type: 'class_level', classId: 'fighter', level: 6 },
    ],
    effects: [
      { type: 'special', description: 'Increase DC of concentration checks for enemies casting defensively within your threatened area by +4.' },
    ],
    repeatable: false,
    summary: 'Enemies in your threatened area have +4 DC to cast defensively.',
  },
  {
    id: 'dodge',
    name: 'Dodge',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'dexterity', minimum: 13 },
    ],
    effects: [
      { type: 'bonus', target: 'ac', bonus: 1, bonusType: 'dodge' },
    ],
    repeatable: false,
    summary: '+1 dodge bonus to AC.',
  },
  {
    id: 'double_slice',
    name: 'Double Slice',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'dexterity', minimum: 15 },
      { type: 'feat', feat: 'two_weapon_fighting' },
    ],
    effects: [
      { type: 'offhand_full_str' },
    ],
    repeatable: false,
    summary: 'Add full STR modifier to off-hand damage (instead of half).',
  },

  // ─── E ─────────────────────────────────────────────────────

  {
    id: 'exhausting_critical',
    name: 'Exhausting Critical',
    category: 'combat',
    prerequisites: [
      { type: 'feat', feat: 'critical_focus' },
      { type: 'feat', feat: 'tiring_critical' },
      { type: 'bab', minimum: 15 },
    ],
    effects: [
      { type: 'on_critical', effect: 'Target is exhausted.' },
    ],
    repeatable: false,
    summary: 'On confirmed critical, target is exhausted.',
  },
  {
    id: 'exotic_weapon_proficiency',
    name: 'Exotic Weapon Proficiency',
    category: 'combat',
    prerequisites: [
      { type: 'bab', minimum: 1 },
    ],
    effects: [
      { type: 'proficiency', category: 'one exotic weapon' },
    ],
    repeatable: true,
    choiceType: 'weapon',
    summary: 'Gain proficiency with one exotic weapon.',
  },

  // ─── F ─────────────────────────────────────────────────────

  {
    id: 'far_shot',
    name: 'Far Shot',
    category: 'combat',
    prerequisites: [
      { type: 'feat', feat: 'point_blank_shot' },
    ],
    effects: [
      { type: 'special', description: 'Reduce ranged penalties: -1 per range increment (projectile) or -1 per 2 increments (thrown) instead of normal -2.' },
    ],
    repeatable: false,
    summary: 'Reduce range increment penalties for ranged weapons.',
  },

  // ─── G ─────────────────────────────────────────────────────

  {
    id: 'gorgons_fist',
    name: "Gorgon's Fist",
    category: 'combat',
    prerequisites: [
      { type: 'feat', feat: 'improved_unarmed_strike' },
      { type: 'feat', feat: 'scorpion_style' },
      { type: 'bab', minimum: 6 },
    ],
    effects: [
      { type: 'action', actionType: 'standard', name: "Gorgon's Fist", effect: 'Unarmed strike against dazed, flat-footed, or stunned foe. On hit, target is staggered until end of your next turn (Fort DC 10 + 1/2 level + WIS mod negates).' },
    ],
    repeatable: false,
    summary: 'Unarmed strike vs impaired foe can stagger (Fort negates).',
  },
  {
    id: 'great_cleave',
    name: 'Great Cleave',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'strength', minimum: 13 },
      { type: 'feat', feat: 'cleave' },
      { type: 'feat', feat: 'power_attack' },
      { type: 'bab', minimum: 4 },
    ],
    effects: [
      { type: 'action', actionType: 'standard', name: 'Great Cleave', effect: 'As Cleave, but no limit on number of extra attacks as long as each target is adjacent to the previous.' },
    ],
    repeatable: false,
    summary: 'Cleave with unlimited extra attacks against adjacent foes.',
  },
  {
    id: 'greater_bull_rush',
    name: 'Greater Bull Rush',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'strength', minimum: 13 },
      { type: 'feat', feat: 'improved_bull_rush' },
      { type: 'feat', feat: 'power_attack' },
      { type: 'bab', minimum: 6 },
    ],
    effects: [
      { type: 'combat_maneuver', maneuver: 'bull rush', cmbBonus: 2, cmdBonus: 2, additionalEffect: 'Targets of your bull rush provoke AoOs from your allies.' },
    ],
    repeatable: false,
    summary: '+2 CMB/CMD for bull rush. Bull rushed targets provoke AoO.',
  },
  {
    id: 'greater_disarm',
    name: 'Greater Disarm',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'intelligence', minimum: 13 },
      { type: 'feat', feat: 'combat_expertise' },
      { type: 'feat', feat: 'improved_disarm' },
      { type: 'bab', minimum: 6 },
    ],
    effects: [
      { type: 'combat_maneuver', maneuver: 'disarm', cmbBonus: 2, cmdBonus: 2, additionalEffect: 'Disarmed weapon lands 15 ft away in random direction.' },
    ],
    repeatable: false,
    summary: '+2 CMB/CMD for disarm. Disarmed weapon is flung 15 ft away.',
  },
  {
    id: 'greater_feint',
    name: 'Greater Feint',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'intelligence', minimum: 13 },
      { type: 'feat', feat: 'combat_expertise' },
      { type: 'feat', feat: 'improved_feint' },
      { type: 'bab', minimum: 6 },
    ],
    effects: [
      { type: 'special', description: 'When you successfully feint, target loses DEX bonus to AC against all attacks until start of your next turn (not just your next attack).' },
    ],
    repeatable: false,
    summary: 'Successful feint makes target lose DEX to AC vs all attacks until your next turn.',
  },
  {
    id: 'greater_grapple',
    name: 'Greater Grapple',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'dexterity', minimum: 13 },
      { type: 'feat', feat: 'improved_grapple' },
      { type: 'feat', feat: 'improved_unarmed_strike' },
      { type: 'bab', minimum: 6 },
    ],
    effects: [
      { type: 'combat_maneuver', maneuver: 'grapple', cmbBonus: 2, cmdBonus: 2, additionalEffect: 'Maintain grapple as a move action instead of standard.' },
    ],
    repeatable: false,
    summary: '+2 CMB/CMD for grapple. Maintain grapple as move action.',
  },
  {
    id: 'greater_overrun',
    name: 'Greater Overrun',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'strength', minimum: 13 },
      { type: 'feat', feat: 'improved_overrun' },
      { type: 'feat', feat: 'power_attack' },
      { type: 'bab', minimum: 6 },
    ],
    effects: [
      { type: 'combat_maneuver', maneuver: 'overrun', cmbBonus: 2, cmdBonus: 2, additionalEffect: 'Targets of your overrun provoke AoOs from your allies when knocked prone.' },
    ],
    repeatable: false,
    summary: '+2 CMB/CMD for overrun. Overrun targets provoke AoO when knocked prone.',
  },
  {
    id: 'greater_penetrating_strike',
    name: 'Greater Penetrating Strike',
    category: 'combat',
    prerequisites: [
      { type: 'feat', feat: 'penetrating_strike' },
      { type: 'feat', feat: 'weapon_focus' },
      { type: 'class_level', classId: 'fighter', level: 16 },
    ],
    effects: [
      { type: 'ignore_dr', amount: 10, condition: 'with focused weapon (except DR/—)' },
    ],
    repeatable: false,
    summary: 'Ignore up to 10 points of DR with focused weapon (except DR/—).',
  },
  {
    id: 'greater_shield_focus',
    name: 'Greater Shield Focus',
    category: 'combat',
    prerequisites: [
      { type: 'feat', feat: 'shield_focus' },
      { type: 'class_level', classId: 'fighter', level: 8 },
    ],
    effects: [
      { type: 'bonus', target: 'ac', bonus: 1, bonusType: 'shield' },
    ],
    repeatable: false,
    summary: '+1 additional shield bonus to AC.',
  },
  {
    id: 'greater_sunder',
    name: 'Greater Sunder',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'strength', minimum: 13 },
      { type: 'feat', feat: 'improved_sunder' },
      { type: 'feat', feat: 'power_attack' },
      { type: 'bab', minimum: 6 },
    ],
    effects: [
      { type: 'combat_maneuver', maneuver: 'sunder', cmbBonus: 2, cmdBonus: 2, additionalEffect: 'Excess damage from sunder applies to the item wielder.' },
    ],
    repeatable: false,
    summary: '+2 CMB/CMD for sunder. Excess damage transfers to wielder.',
  },
  {
    id: 'greater_trip',
    name: 'Greater Trip',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'intelligence', minimum: 13 },
      { type: 'feat', feat: 'combat_expertise' },
      { type: 'feat', feat: 'improved_trip' },
      { type: 'bab', minimum: 6 },
    ],
    effects: [
      { type: 'combat_maneuver', maneuver: 'trip', cmbBonus: 2, cmdBonus: 2, additionalEffect: 'Tripped targets provoke AoOs from you and your allies.' },
    ],
    repeatable: false,
    summary: '+2 CMB/CMD for trip. Tripped targets provoke AoO.',
  },
  {
    id: 'greater_two_weapon_fighting',
    name: 'Greater Two-Weapon Fighting',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'dexterity', minimum: 19 },
      { type: 'feat', feat: 'improved_two_weapon_fighting' },
      { type: 'feat', feat: 'two_weapon_fighting' },
      { type: 'bab', minimum: 11 },
    ],
    effects: [
      { type: 'extra_attack', attackType: 'off-hand (third)', penalty: -10, condition: 'when fighting with two weapons' },
    ],
    repeatable: false,
    summary: 'Gain a third off-hand attack at -10 penalty.',
  },
  {
    id: 'greater_vital_strike',
    name: 'Greater Vital Strike',
    category: 'combat',
    prerequisites: [
      { type: 'feat', feat: 'improved_vital_strike' },
      { type: 'feat', feat: 'vital_strike' },
      { type: 'bab', minimum: 16 },
    ],
    effects: [
      { type: 'extra_weapon_dice', multiplier: 3 },
    ],
    repeatable: false,
    summary: 'Roll weapon damage dice 4 times on a single attack (3 extra).',
  },
  {
    id: 'greater_weapon_focus',
    name: 'Greater Weapon Focus',
    category: 'combat',
    prerequisites: [
      { type: 'feat', feat: 'weapon_focus' },
      { type: 'class_level', classId: 'fighter', level: 8 },
    ],
    effects: [
      { type: 'bonus', target: 'attack', bonus: 1, condition: 'with chosen weapon' },
    ],
    repeatable: true,
    choiceType: 'weapon',
    summary: '+1 additional attack bonus with chosen weapon.',
  },
  {
    id: 'greater_weapon_specialization',
    name: 'Greater Weapon Specialization',
    category: 'combat',
    prerequisites: [
      { type: 'feat', feat: 'weapon_specialization' },
      { type: 'feat', feat: 'greater_weapon_focus' },
      { type: 'class_level', classId: 'fighter', level: 12 },
    ],
    effects: [
      { type: 'bonus', target: 'damage', bonus: 2, condition: 'with chosen weapon' },
    ],
    repeatable: true,
    choiceType: 'weapon',
    summary: '+2 additional damage with chosen weapon.',
  },

  // ─── I ─────────────────────────────────────────────────────

  {
    id: 'improved_bull_rush',
    name: 'Improved Bull Rush',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'strength', minimum: 13 },
      { type: 'feat', feat: 'power_attack' },
      { type: 'bab', minimum: 1 },
    ],
    effects: [
      { type: 'combat_maneuver', maneuver: 'bull rush', cmbBonus: 2, cmdBonus: 2, noAoO: true },
    ],
    repeatable: false,
    summary: '+2 CMB/CMD for bull rush. Does not provoke AoO.',
  },
  {
    id: 'improved_critical',
    name: 'Improved Critical',
    category: 'combat',
    prerequisites: [
      { type: 'proficiency', weapon: 'chosen weapon' },
      { type: 'bab', minimum: 8 },
    ],
    effects: [
      { type: 'double_threat_range', weapon: 'chosen weapon' },
    ],
    repeatable: true,
    choiceType: 'weapon',
    summary: 'Double the critical threat range of chosen weapon.',
  },
  {
    id: 'improved_disarm',
    name: 'Improved Disarm',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'intelligence', minimum: 13 },
      { type: 'feat', feat: 'combat_expertise' },
    ],
    effects: [
      { type: 'combat_maneuver', maneuver: 'disarm', cmbBonus: 2, cmdBonus: 2, noAoO: true },
    ],
    repeatable: false,
    summary: '+2 CMB/CMD for disarm. Does not provoke AoO.',
  },
  {
    id: 'improved_feint',
    name: 'Improved Feint',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'intelligence', minimum: 13 },
      { type: 'feat', feat: 'combat_expertise' },
    ],
    effects: [
      { type: 'special', description: 'Can feint in combat as a move action instead of a standard action.' },
    ],
    repeatable: false,
    summary: 'Feint as a move action instead of standard.',
  },
  {
    id: 'improved_grapple',
    name: 'Improved Grapple',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'dexterity', minimum: 13 },
      { type: 'feat', feat: 'improved_unarmed_strike' },
    ],
    effects: [
      { type: 'combat_maneuver', maneuver: 'grapple', cmbBonus: 2, cmdBonus: 2, noAoO: true },
    ],
    repeatable: false,
    summary: '+2 CMB/CMD for grapple. Does not provoke AoO.',
  },
  {
    id: 'improved_initiative',
    name: 'Improved Initiative',
    category: 'combat',
    prerequisites: [],
    effects: [
      { type: 'bonus', target: 'initiative', bonus: 4 },
    ],
    repeatable: false,
    summary: '+4 bonus to initiative.',
  },
  {
    id: 'improved_overrun',
    name: 'Improved Overrun',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'strength', minimum: 13 },
      { type: 'feat', feat: 'power_attack' },
      { type: 'bab', minimum: 1 },
    ],
    effects: [
      { type: 'combat_maneuver', maneuver: 'overrun', cmbBonus: 2, cmdBonus: 2, noAoO: true },
      { type: 'special', description: 'Targets of your overrun cannot choose to avoid you.' },
    ],
    repeatable: false,
    summary: '+2 CMB/CMD for overrun. Does not provoke AoO. Foes cannot avoid.',
  },
  {
    id: 'improved_precise_shot',
    name: 'Improved Precise Shot',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'dexterity', minimum: 19 },
      { type: 'feat', feat: 'point_blank_shot' },
      { type: 'feat', feat: 'precise_shot' },
      { type: 'bab', minimum: 11 },
    ],
    effects: [
      { type: 'negate_penalty', penalty: 'target_cover_ac', description: 'Ranged attacks ignore anything less than total cover and anything less than total concealment.' },
    ],
    repeatable: false,
    summary: 'Ranged attacks ignore less-than-total cover and concealment.',
  },
  {
    id: 'improved_shield_bash',
    name: 'Improved Shield Bash',
    category: 'combat',
    prerequisites: [
      { type: 'proficiency', weapon: 'shield' },
    ],
    effects: [
      { type: 'negate_penalty', penalty: 'shield_ac_loss_on_bash', description: 'Retain shield bonus to AC when making a shield bash attack.' },
    ],
    repeatable: false,
    summary: 'Keep shield AC bonus when shield bashing.',
  },
  {
    id: 'improved_sunder',
    name: 'Improved Sunder',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'strength', minimum: 13 },
      { type: 'feat', feat: 'power_attack' },
      { type: 'bab', minimum: 1 },
    ],
    effects: [
      { type: 'combat_maneuver', maneuver: 'sunder', cmbBonus: 2, cmdBonus: 2, noAoO: true },
    ],
    repeatable: false,
    summary: '+2 CMB/CMD for sunder. Does not provoke AoO.',
  },
  {
    id: 'improved_trip',
    name: 'Improved Trip',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'intelligence', minimum: 13 },
      { type: 'feat', feat: 'combat_expertise' },
    ],
    effects: [
      { type: 'combat_maneuver', maneuver: 'trip', cmbBonus: 2, cmdBonus: 2, noAoO: true },
    ],
    repeatable: false,
    summary: '+2 CMB/CMD for trip. Does not provoke AoO.',
  },
  {
    id: 'improved_two_weapon_fighting',
    name: 'Improved Two-Weapon Fighting',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'dexterity', minimum: 17 },
      { type: 'feat', feat: 'two_weapon_fighting' },
      { type: 'bab', minimum: 6 },
    ],
    effects: [
      { type: 'extra_attack', attackType: 'off-hand (second)', penalty: -5, condition: 'when fighting with two weapons' },
    ],
    repeatable: false,
    summary: 'Gain a second off-hand attack at -5 penalty.',
  },
  {
    id: 'improved_unarmed_strike',
    name: 'Improved Unarmed Strike',
    category: 'combat',
    prerequisites: [],
    effects: [
      { type: 'special', description: 'Unarmed attacks do not provoke AoOs. May deal lethal or nonlethal damage with unarmed strikes.' },
    ],
    repeatable: false,
    summary: 'Unarmed strikes do not provoke AoO. Deal lethal or nonlethal.',
  },
  {
    id: 'improved_vital_strike',
    name: 'Improved Vital Strike',
    category: 'combat',
    prerequisites: [
      { type: 'feat', feat: 'vital_strike' },
      { type: 'bab', minimum: 11 },
    ],
    effects: [
      { type: 'extra_weapon_dice', multiplier: 2 },
    ],
    repeatable: false,
    summary: 'Roll weapon damage dice 3 times on a single attack (2 extra).',
  },
  {
    id: 'improvised_weapon_mastery',
    name: 'Improvised Weapon Mastery',
    category: 'combat',
    prerequisites: [
      { type: 'bab', minimum: 8 },
    ],
    effects: [
      { type: 'special', description: 'Improvised weapons deal damage one size larger. Critical threat range is 19-20. Do not provoke AoOs with improvised weapons.' },
    ],
    repeatable: false,
    summary: 'Improvised weapons deal increased damage, crit on 19-20.',
  },

  // ─── L ─────────────────────────────────────────────────────

  {
    id: 'lightning_stance',
    name: 'Lightning Stance',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'dexterity', minimum: 17 },
      { type: 'feat', feat: 'dodge' },
      { type: 'feat', feat: 'wind_stance' },
      { type: 'bab', minimum: 11 },
    ],
    effects: [
      { type: 'miss_chance', percent: 50, condition: 'when you take two or more actions to move in a round' },
    ],
    repeatable: false,
    summary: '50% miss chance against you after taking two move actions in a round.',
  },
  {
    id: 'lunge',
    name: 'Lunge',
    category: 'combat',
    prerequisites: [
      { type: 'bab', minimum: 6 },
    ],
    effects: [
      { type: 'special', description: 'Increase melee reach by 5 ft until end of turn at the cost of -2 to AC until start of next turn.' },
    ],
    repeatable: false,
    summary: '+5 ft melee reach until end of turn, -2 AC until next turn.',
  },

  // ─── M ─────────────────────────────────────────────────────

  {
    id: 'manyshot',
    name: 'Manyshot',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'dexterity', minimum: 17 },
      { type: 'feat', feat: 'point_blank_shot' },
      { type: 'feat', feat: 'rapid_shot' },
      { type: 'bab', minimum: 6 },
    ],
    effects: [
      { type: 'special', description: 'Fire two arrows on your first ranged attack at full BAB. Both use the same attack roll; damage for each is calculated separately.' },
    ],
    repeatable: false,
    summary: 'Fire two arrows on first attack of a full-attack action.',
  },
  {
    id: 'mobility',
    name: 'Mobility',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'dexterity', minimum: 13 },
      { type: 'feat', feat: 'dodge' },
    ],
    effects: [
      { type: 'bonus', target: 'ac', bonus: 4, bonusType: 'dodge', condition: 'against AoOs provoked by movement' },
    ],
    repeatable: false,
    summary: '+4 dodge AC against AoOs caused by movement.',
  },
  {
    id: 'mounted_archery',
    name: 'Mounted Archery',
    category: 'combat',
    prerequisites: [
      { type: 'skill', skill: 'Ride', ranks: 1 },
      { type: 'feat', feat: 'mounted_combat' },
    ],
    effects: [
      { type: 'mounted', description: 'Ranged attack penalties while mounted are halved (-2 at a walk or hustle, -4 at a gallop).' },
    ],
    repeatable: false,
    summary: 'Halve ranged attack penalties while mounted.',
  },
  {
    id: 'mounted_combat',
    name: 'Mounted Combat',
    category: 'combat',
    prerequisites: [
      { type: 'skill', skill: 'Ride', ranks: 1 },
    ],
    effects: [
      { type: 'mounted', description: 'Once per round, negate a hit on your mount by making a Ride check (DC = attack roll result).' },
    ],
    repeatable: false,
    summary: 'Negate one hit on mount per round with a Ride check.',
  },

  // ─── P ─────────────────────────────────────────────────────

  {
    id: 'penetrating_strike',
    name: 'Penetrating Strike',
    category: 'combat',
    prerequisites: [
      { type: 'feat', feat: 'weapon_focus' },
      { type: 'class_level', classId: 'fighter', level: 12 },
    ],
    effects: [
      { type: 'ignore_dr', amount: 5, condition: 'with focused weapon (except DR/—)' },
    ],
    repeatable: false,
    summary: 'Ignore up to 5 points of DR with focused weapon (except DR/—).',
  },
  {
    id: 'pinpoint_targeting',
    name: 'Pinpoint Targeting',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'dexterity', minimum: 19 },
      { type: 'feat', feat: 'improved_precise_shot' },
      { type: 'feat', feat: 'point_blank_shot' },
      { type: 'feat', feat: 'precise_shot' },
      { type: 'bab', minimum: 16 },
    ],
    effects: [
      { type: 'action', actionType: 'standard', name: 'Pinpoint Targeting', effect: 'Make a single ranged attack that resolves against touch AC instead of normal AC.' },
    ],
    repeatable: false,
    summary: 'Standard action: single ranged attack vs touch AC.',
  },
  {
    id: 'point_blank_shot',
    name: 'Point-Blank Shot',
    category: 'combat',
    prerequisites: [],
    effects: [
      { type: 'bonus', target: 'ranged_attack', bonus: 1, condition: 'within 30 ft' },
      { type: 'bonus', target: 'ranged_damage', bonus: 1, condition: 'within 30 ft' },
    ],
    repeatable: false,
    summary: '+1 attack and +1 damage on ranged attacks within 30 ft.',
  },
  {
    id: 'power_attack',
    name: 'Power Attack',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'strength', minimum: 13 },
      { type: 'bab', minimum: 1 },
    ],
    effects: [
      { type: 'attack_damage_trade', attackPenalty: -1, damageBonus: 2, twoHandedDamageBonus: 3, scalingPerBAB: 4 },
    ],
    repeatable: false,
    summary: 'Trade melee attack for damage. -1 attack/+2 damage (+3 two-handed), scaling every 4 BAB.',
  },
  {
    id: 'precise_shot',
    name: 'Precise Shot',
    category: 'combat',
    prerequisites: [
      { type: 'feat', feat: 'point_blank_shot' },
    ],
    effects: [
      { type: 'negate_penalty', penalty: 'shooting_into_melee', description: 'No -4 penalty for shooting or throwing into melee.' },
    ],
    repeatable: false,
    summary: 'No penalty for shooting into melee.',
  },

  // ─── R ─────────────────────────────────────────────────────

  {
    id: 'rapid_reload',
    name: 'Rapid Reload',
    category: 'combat',
    prerequisites: [
      { type: 'proficiency', weapon: 'chosen crossbow or firearm' },
    ],
    effects: [
      { type: 'special', description: 'Reload chosen crossbow or firearm faster: light crossbow/hand crossbow as free action; heavy crossbow as move action.' },
    ],
    repeatable: true,
    choiceType: 'weapon',
    summary: 'Reload a crossbow faster (light=free, heavy=move action).',
  },
  {
    id: 'rapid_shot',
    name: 'Rapid Shot',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'dexterity', minimum: 13 },
      { type: 'feat', feat: 'point_blank_shot' },
    ],
    effects: [
      { type: 'extra_attack', attackType: 'ranged', penalty: -2, condition: 'all attacks in a full-attack take -2' },
    ],
    repeatable: false,
    summary: 'One extra ranged attack at highest BAB in full attack; all attacks at -2.',
  },
  {
    id: 'ride_by_attack',
    name: 'Ride-By Attack',
    category: 'combat',
    prerequisites: [
      { type: 'skill', skill: 'Ride', ranks: 1 },
      { type: 'feat', feat: 'mounted_combat' },
    ],
    effects: [
      { type: 'mounted', description: 'When mounted and charging, move before and after the attack. Total distance cannot exceed mount speed.' },
    ],
    repeatable: false,
    summary: 'Move before and after a mounted charge attack.',
  },

  // ─── S ─────────────────────────────────────────────────────

  {
    id: 'scorpion_style',
    name: 'Scorpion Style',
    category: 'combat',
    prerequisites: [
      { type: 'feat', feat: 'improved_unarmed_strike' },
    ],
    effects: [
      { type: 'action', actionType: 'standard', name: 'Scorpion Style', effect: 'Unarmed strike; on hit target speed reduced to 5 ft for a number of rounds equal to your WIS modifier (Fort DC 10 + 1/2 level + WIS mod negates).' },
    ],
    repeatable: false,
    summary: 'Unarmed strike reduces target speed to 5 ft (Fort negates).',
  },
  {
    id: 'shatter_defenses',
    name: 'Shatter Defenses',
    category: 'combat',
    prerequisites: [
      { type: 'feat', feat: 'weapon_focus' },
      { type: 'feat', feat: 'dazzling_display' },
      { type: 'bab', minimum: 6 },
    ],
    effects: [
      { type: 'special', description: 'Any shaken, frightened, or panicked foe you hit is flat-footed to your attacks until the end of your next turn.' },
    ],
    repeatable: false,
    summary: 'Shaken/frightened foes you hit become flat-footed to your attacks.',
  },
  {
    id: 'shield_focus',
    name: 'Shield Focus',
    category: 'combat',
    prerequisites: [
      { type: 'proficiency', weapon: 'shield' },
      { type: 'bab', minimum: 1 },
    ],
    effects: [
      { type: 'bonus', target: 'ac', bonus: 1, bonusType: 'shield' },
    ],
    repeatable: false,
    summary: '+1 shield bonus to AC.',
  },
  {
    id: 'shield_master',
    name: 'Shield Master',
    category: 'combat',
    prerequisites: [
      { type: 'feat', feat: 'improved_shield_bash' },
      { type: 'feat', feat: 'shield_slam' },
      { type: 'feat', feat: 'two_weapon_fighting' },
      { type: 'bab', minimum: 11 },
    ],
    effects: [
      { type: 'negate_penalty', penalty: 'twf_shield_penalty', description: 'No TWF penalty when using a shield as off-hand weapon.' },
      { type: 'special', description: 'Add shield enhancement bonus to attack and damage rolls made with the shield.' },
    ],
    repeatable: false,
    summary: 'No TWF penalty with shield. Add shield enhancement to attack/damage.',
  },
  {
    id: 'shield_slam',
    name: 'Shield Slam',
    category: 'combat',
    prerequisites: [
      { type: 'feat', feat: 'improved_shield_bash' },
      { type: 'feat', feat: 'two_weapon_fighting' },
      { type: 'bab', minimum: 6 },
    ],
    effects: [
      { type: 'special', description: 'On shield bash hit during a full attack, free bull rush (does not provoke AoO). If bull rush pushes into wall or obstacle, target takes additional 1d6+STR damage.' },
    ],
    repeatable: false,
    summary: 'Free bull rush on shield bash hit; extra damage if pushed into wall.',
  },
  {
    id: 'shot_on_the_run',
    name: 'Shot on the Run',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'dexterity', minimum: 13 },
      { type: 'feat', feat: 'dodge' },
      { type: 'feat', feat: 'mobility' },
      { type: 'feat', feat: 'point_blank_shot' },
      { type: 'bab', minimum: 4 },
    ],
    effects: [
      { type: 'movement', description: 'Move before and after a ranged attack. Total distance cannot exceed speed.' },
    ],
    repeatable: false,
    summary: 'Move before and after a single ranged attack.',
  },
  {
    id: 'sickening_critical',
    name: 'Sickening Critical',
    category: 'combat',
    prerequisites: [
      { type: 'feat', feat: 'critical_focus' },
      { type: 'bab', minimum: 11 },
    ],
    effects: [
      { type: 'on_critical', effect: 'Target is sickened for 1 minute.', save: { saveType: 'fort', dc: '10 + BAB' } },
    ],
    repeatable: false,
    summary: 'On confirmed critical, target is sickened for 1 minute (Fort negates).',
  },
  {
    id: 'snatch_arrows',
    name: 'Snatch Arrows',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'dexterity', minimum: 15 },
      { type: 'feat', feat: 'deflect_arrows' },
      { type: 'feat', feat: 'improved_unarmed_strike' },
    ],
    effects: [
      { type: 'special', description: 'When you deflect a ranged attack, you catch it. You may throw it back as a free action at the original attacker.' },
    ],
    repeatable: false,
    summary: 'Catch deflected arrows and throw them back as a free action.',
  },
  {
    id: 'spellbreaker',
    name: 'Spellbreaker',
    category: 'combat',
    prerequisites: [
      { type: 'feat', feat: 'disruptive' },
      { type: 'class_level', classId: 'fighter', level: 10 },
    ],
    effects: [
      { type: 'special', description: 'Enemies in your threatened area that fail concentration checks for casting defensively provoke an AoO from you.' },
    ],
    repeatable: false,
    summary: 'Foes who fail defensive casting in your reach provoke AoO.',
  },
  {
    id: 'spirited_charge',
    name: 'Spirited Charge',
    category: 'combat',
    prerequisites: [
      { type: 'skill', skill: 'Ride', ranks: 1 },
      { type: 'feat', feat: 'mounted_combat' },
      { type: 'feat', feat: 'ride_by_attack' },
    ],
    effects: [
      { type: 'charge_damage_multiplier', multiplier: 2, condition: 'on mounted charge (x3 with lance)' },
    ],
    repeatable: false,
    summary: 'Double damage on mounted charge (triple with lance).',
  },
  {
    id: 'spring_attack',
    name: 'Spring Attack',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'dexterity', minimum: 13 },
      { type: 'feat', feat: 'dodge' },
      { type: 'feat', feat: 'mobility' },
      { type: 'bab', minimum: 4 },
    ],
    effects: [
      { type: 'movement', description: 'Move before and after a melee attack. Target does not get AoO. Total distance cannot exceed speed.' },
    ],
    repeatable: false,
    summary: 'Move before and after a melee attack without provoking AoO from target.',
  },
  {
    id: 'staggering_critical',
    name: 'Staggering Critical',
    category: 'combat',
    prerequisites: [
      { type: 'feat', feat: 'critical_focus' },
      { type: 'bab', minimum: 13 },
    ],
    effects: [
      { type: 'on_critical', effect: 'Target is staggered for 1d4+1 rounds.', save: { saveType: 'fort', dc: '10 + BAB' } },
    ],
    repeatable: false,
    summary: 'On confirmed critical, target is staggered for 1d4+1 rounds (Fort negates).',
  },
  {
    id: 'step_up',
    name: 'Step Up',
    category: 'combat',
    prerequisites: [
      { type: 'bab', minimum: 1 },
    ],
    effects: [
      { type: 'special', description: 'When an adjacent foe takes a 5-ft step away from you, you may take an immediate 5-ft step to follow.' },
    ],
    repeatable: false,
    summary: "Take an immediate 5-ft step when an adjacent foe 5-ft steps away.",
  },
  {
    id: 'stunning_critical',
    name: 'Stunning Critical',
    category: 'combat',
    prerequisites: [
      { type: 'feat', feat: 'critical_focus' },
      { type: 'feat', feat: 'staggering_critical' },
      { type: 'bab', minimum: 17 },
    ],
    effects: [
      { type: 'on_critical', effect: 'Target is stunned for 1d4 rounds.', save: { saveType: 'fort', dc: '10 + BAB' } },
    ],
    repeatable: false,
    summary: 'On confirmed critical, target is stunned for 1d4 rounds (Fort negates).',
  },
  {
    id: 'stunning_fist',
    name: 'Stunning Fist',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'dexterity', minimum: 13 },
      { type: 'ability', ability: 'wisdom', minimum: 13 },
      { type: 'feat', feat: 'improved_unarmed_strike' },
      { type: 'bab', minimum: 8 },
    ],
    effects: [
      { type: 'daily_use', name: 'Stunning Fist', usesPerDay: 'level / 4 (minimum 1)', effect: 'Declare before unarmed attack. On hit, target is stunned for 1 round.', save: { saveType: 'fort', dc: '10 + 1/2 character level + WIS modifier' } },
    ],
    repeatable: false,
    summary: 'Unarmed strike can stun (Fort negates). Uses/day = level/4 (min 1).',
  },

  // ─── T ─────────────────────────────────────────────────────

  {
    id: 'throw_anything',
    name: 'Throw Anything',
    category: 'combat',
    prerequisites: [],
    effects: [
      { type: 'negate_penalty', penalty: 'improvised_thrown_weapons', description: 'No penalty for using improvised thrown weapons.' },
      { type: 'bonus', target: 'damage', bonus: 1, condition: 'splash weapon damage' },
    ],
    repeatable: false,
    summary: 'No improvised thrown penalty. +1 damage with splash weapons.',
  },
  {
    id: 'tiring_critical',
    name: 'Tiring Critical',
    category: 'combat',
    prerequisites: [
      { type: 'feat', feat: 'critical_focus' },
      { type: 'bab', minimum: 13 },
    ],
    effects: [
      { type: 'on_critical', effect: 'Target is fatigued.' },
    ],
    repeatable: false,
    summary: 'On confirmed critical, target is fatigued.',
  },
  {
    id: 'trample',
    name: 'Trample',
    category: 'combat',
    prerequisites: [
      { type: 'skill', skill: 'Ride', ranks: 1 },
      { type: 'feat', feat: 'mounted_combat' },
    ],
    effects: [
      { type: 'mounted', description: 'When mounted, you can overrun as part of a charge. Targets that fail to avoid take hoof damage and you can make your attack at any point during the overrun.' },
    ],
    repeatable: false,
    summary: 'Overrun as part of mounted charge. Targets take hoof damage.',
  },
  {
    id: 'two_weapon_defense',
    name: 'Two-Weapon Defense',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'dexterity', minimum: 15 },
      { type: 'feat', feat: 'two_weapon_fighting' },
    ],
    effects: [
      { type: 'bonus', target: 'ac', bonus: 1, bonusType: 'shield', condition: 'when wielding two weapons (or weapon and shield) and fighting defensively or using total defense' },
    ],
    repeatable: false,
    summary: '+1 shield bonus to AC when fighting with two weapons.',
  },
  {
    id: 'two_weapon_fighting',
    name: 'Two-Weapon Fighting',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'dexterity', minimum: 15 },
    ],
    effects: [
      { type: 'twf_penalty_reduction', mainHandReduction: 2, offHandReduction: 6 },
    ],
    repeatable: false,
    summary: 'Reduce TWF penalties: -2 main / -2 off-hand (with light off-hand).',
  },
  {
    id: 'two_weapon_rend',
    name: 'Two-Weapon Rend',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'dexterity', minimum: 17 },
      { type: 'feat', feat: 'double_slice' },
      { type: 'feat', feat: 'improved_two_weapon_fighting' },
      { type: 'feat', feat: 'two_weapon_fighting' },
      { type: 'bab', minimum: 11 },
    ],
    effects: [
      { type: 'special', description: 'When you hit with both main and off-hand weapons in the same round, deal an extra 1d10 + 1.5 × STR modifier damage.' },
    ],
    repeatable: false,
    summary: 'Extra 1d10 + 1.5×STR damage when hitting with both weapons.',
  },

  // ─── U ─────────────────────────────────────────────────────

  {
    id: 'unseat',
    name: 'Unseat',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'strength', minimum: 13 },
      { type: 'skill', skill: 'Ride', ranks: 1 },
      { type: 'feat', feat: 'mounted_combat' },
      { type: 'feat', feat: 'power_attack' },
      { type: 'feat', feat: 'improved_bull_rush' },
      { type: 'feat', feat: 'ride_by_attack' },
    ],
    effects: [
      { type: 'mounted', description: 'On a mounted charge with a lance, attempt a bull rush instead of a normal attack. If successful, target is knocked from saddle.' },
    ],
    repeatable: false,
    summary: 'Mounted lance charge can unhorse opponent via bull rush.',
  },

  // ─── V ─────────────────────────────────────────────────────

  {
    id: 'vital_strike',
    name: 'Vital Strike',
    category: 'combat',
    prerequisites: [
      { type: 'bab', minimum: 6 },
    ],
    effects: [
      { type: 'extra_weapon_dice', multiplier: 1 },
    ],
    repeatable: false,
    summary: 'Roll weapon damage dice 2 times on a single attack (1 extra).',
  },

  // ─── W ─────────────────────────────────────────────────────

  {
    id: 'weapon_finesse',
    name: 'Weapon Finesse',
    category: 'combat',
    prerequisites: [],
    effects: [
      { type: 'replace_modifier', from: 'STR', to: 'DEX', forRoll: 'melee attack rolls with light or finesse weapons' },
    ],
    repeatable: false,
    summary: 'Use DEX instead of STR for attack rolls with light/finesse weapons.',
  },
  {
    id: 'weapon_focus',
    name: 'Weapon Focus',
    category: 'combat',
    prerequisites: [
      { type: 'proficiency', weapon: 'chosen weapon' },
      { type: 'bab', minimum: 1 },
    ],
    effects: [
      { type: 'bonus', target: 'attack', bonus: 1, condition: 'with chosen weapon' },
    ],
    repeatable: true,
    choiceType: 'weapon',
    summary: '+1 attack with chosen weapon.',
  },
  {
    id: 'weapon_specialization',
    name: 'Weapon Specialization',
    category: 'combat',
    prerequisites: [
      { type: 'feat', feat: 'weapon_focus' },
      { type: 'class_level', classId: 'fighter', level: 4 },
    ],
    effects: [
      { type: 'bonus', target: 'damage', bonus: 2, condition: 'with chosen weapon' },
    ],
    repeatable: true,
    choiceType: 'weapon',
    summary: '+2 damage with chosen weapon.',
  },
  {
    id: 'whirlwind_attack',
    name: 'Whirlwind Attack',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'dexterity', minimum: 13 },
      { type: 'ability', ability: 'intelligence', minimum: 13 },
      { type: 'feat', feat: 'combat_expertise' },
      { type: 'feat', feat: 'dodge' },
      { type: 'feat', feat: 'mobility' },
      { type: 'feat', feat: 'spring_attack' },
      { type: 'bab', minimum: 4 },
    ],
    effects: [
      { type: 'action', actionType: 'full_round', name: 'Whirlwind Attack', effect: 'Make one melee attack at full BAB against each opponent within reach.' },
    ],
    repeatable: false,
    summary: 'Full-round: one melee attack against each foe within reach.',
  },
  {
    id: 'wind_stance',
    name: 'Wind Stance',
    category: 'combat',
    prerequisites: [
      { type: 'ability', ability: 'dexterity', minimum: 15 },
      { type: 'feat', feat: 'dodge' },
      { type: 'bab', minimum: 6 },
    ],
    effects: [
      { type: 'miss_chance', percent: 20, condition: 'when you move more than 5 ft in a round' },
    ],
    repeatable: false,
    summary: '20% miss chance against you after moving more than 5 ft in a round.',
  },
];
