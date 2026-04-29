# frozen_string_literal: true

module Combat
  # Resolves a single deterministic NPC attack against a target sheet.
  # Used by PR-D's AoO trigger and (later) PR-F's NPC behavior engine.
  # Pure server-side dice — clients never roll for NPCs.
  module NpcAttackResolver
    DEFAULT_NATURAL_DAMAGE = '1d4'

    module_function

    # @param attacker [CreatureSheet]
    # @param target_sheet [CreatureSheet, AdventureSheet]
    # @param target_kind [Symbol]
    # @param attack_pref [Combat::ProgrammedBehavior::AttackPreference, nil]
    # @return [Combat::NpcAttackOutcome]
    def call(attacker:, target_sheet:, target_kind:, attack_pref: nil)
      weapon = pick_weapon_for_attack(attacker, attack_pref)
      attack_bonus = attack_bonus_for(attacker, weapon)
      defense_dc = ac_for(target_sheet)
      attack_roll = roll_attack(attack_bonus, defense_dc)
      damage = attack_roll[:hit] ? roll_damage(attacker, weapon) : nil
      target_state = apply_damage_to(target_sheet, damage)
      summary = Combat::AttackSummary.build(
        actors: { attacker: attacker, target_sheet: target_sheet, target_kind: target_kind },
        weapon: weapon,
        dice: { attack_roll: attack_roll, damage: damage, target_state: target_state }
      )

      Combat::NpcAttackOutcome.new(
        summary: summary, attack_roll: attack_roll, damage: damage, target_state: target_state
      )
    end

    # @param creature [CreatureSheet]
    # @param weapon [Combat::EquippedWeapon]
    def attack_bonus_for(creature, weapon)
      stats = creature.derived_stats || {}
      key = weapon.ranged? ? 'ranged_attack' : 'melee_attack'
      bonus = stats[key] || stats[key.to_sym] || stats['bab'] || stats[:bab]
      bonus.to_i
    end

    # @param creature [CreatureSheet]
    # @param attack_pref [Combat::ProgrammedBehavior::AttackPreference, nil]
    # @return [Combat::EquippedWeapon]
    def pick_weapon_for_attack(creature, attack_pref)
      weapons = Array(creature.equipped_weapons)
      if attack_pref&.name.to_s.match?(/\S/)
        named = weapons.find { |w| weapon_with_dice?(w) && weapon_label_matches?(w, attack_pref.name) }
        return Combat::EquippedWeapon.from_raw(named) if named
      end

      primary_weapon_for(creature)
    end

    # @param weapon [Hash]
    # @param name [String]
    def weapon_label_matches?(weapon, name)
      label = (weapon['name'] || weapon[:name]).to_s
      label.casecmp(name.to_s).zero?
    end

    # @param sheet [CreatureSheet, AdventureSheet]
    def ac_for(sheet)
      stats = sheet.derived_stats || {}
      (stats['ac'] || stats[:ac]).to_i
    end

    # @param creature [CreatureSheet]
    def str_mod(creature)
      mods = (creature.derived_stats || {})['mods'] || {}
      val = mods['strength']
      return val.to_i if val

      ((creature.strength.to_i - 10) / 2).floor
    end

    # @param creature [CreatureSheet]
    # @return [Combat::EquippedWeapon]
    def primary_weapon_for(creature)
      first = Array(creature.equipped_weapons).find { |w| weapon_with_dice?(w) }
      return Combat::EquippedWeapon.from_raw(first) if first

      Combat::EquippedWeapon.natural_attack(DEFAULT_NATURAL_DAMAGE)
    end

    def roll_attack(attack_bonus, defense_dc)
      natural = DungeonMaster::Rolls::CombatDice.roll_d20
      total = natural + attack_bonus
      hit = (total >= defense_dc || natural == 20) && natural != 1
      { hit: hit, natural: natural, total: total, defense_dc: defense_dc }
    end

    # @param attacker [CreatureSheet]
    # @param weapon [Combat::EquippedWeapon]
    # @return [Combat::DamageRoll]
    def roll_damage(attacker, weapon)
      base = DungeonMaster::Rolls::CombatDice.roll_damage_expression(weapon.damage_dice.to_s)
      total = [base + str_mod(attacker), 1].max
      Combat::DamageRoll.new(total: total, type: weapon.damage_type)
    end

    # @param sheet [CreatureSheet, AdventureSheet]
    # @param damage [Combat::DamageRoll, nil] nil when the attack missed
    def apply_damage_to(sheet, damage)
      hp_before = sheet.hp.to_i
      hp_after = hp_before
      dropped = false

      if damage&.total
        hp_after = (hp_before - damage.total).clamp(0, sheet.max_hp.to_i)
        sheet.update!(hp: hp_after)
        dropped = hp_after <= 0
      end

      { hp_before: hp_before, hp_after: hp_after, dropped: dropped }
    end

    # @param weapon [Hash, nil] raw entry from CreatureSheet#equipped_weapons
    def weapon_with_dice?(weapon)
      weapon.is_a?(Hash) && (weapon['damage_dice'] || weapon[:damage_dice]).to_s.match?(/\d+d\d+/)
    end
  end
end
