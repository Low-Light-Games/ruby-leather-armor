# frozen_string_literal: true

module Combat
  # Resolves a single deterministic NPC attack against a target sheet.
  # Used by PR-D's AoO trigger and (later) PR-F's NPC behavior engine.
  # Pure server-side dice — clients never roll for NPCs.
  module NpcAttackResolver
    DEFAULT_NATURAL_DAMAGE = '1d4'

    module_function

    def call(attacker:, target_sheet:, target_kind:)
      attack_bonus = attack_bonus_for(attacker)
      defense_dc = ac_for(target_sheet)
      attack_roll = roll_attack(attack_bonus, defense_dc)
      weapon = primary_weapon_for(attacker)
      damage = attack_roll[:hit] ? roll_damage(attacker, weapon) : nil
      target_state = apply_damage_to(target_sheet, damage)
      summary = build_summary(
        actors: { attacker: attacker, target_sheet: target_sheet, target_kind: target_kind },
        weapon: weapon, attack_roll: attack_roll, damage: damage, target_state: target_state
      )

      Combat::NpcAttackOutcome.new(
        summary: summary, attack_roll: attack_roll, damage: damage, target_state: target_state
      )
    end

    def attack_bonus_for(creature)
      stats = creature.derived_stats || {}
      bonus = stats['melee_attack'] || stats[:melee_attack] || stats['bab'] || stats[:bab]
      bonus.to_i
    end

    def ac_for(sheet)
      stats = sheet.derived_stats || {}
      (stats['ac'] || stats[:ac]).to_i
    end

    def str_mod(creature)
      mods = (creature.derived_stats || {})['mods'] || {}
      val = mods['strength']
      return val.to_i if val

      ((creature.strength.to_i - 10) / 2).floor
    end

    def primary_weapon_for(creature)
      first = Array(creature.equipped_weapons).find { |w| weapon_with_dice?(w) }
      return weapon_payload(first) if first

      { label: 'natural attack', damage: DEFAULT_NATURAL_DAMAGE, damage_type: nil }
    end

    def roll_attack(attack_bonus, defense_dc)
      natural = DungeonMaster::Rolls::CombatDice.roll_d20
      total = natural + attack_bonus
      hit = (total >= defense_dc || natural == 20) && natural != 1
      { hit: hit, natural: natural, total: total, defense_dc: defense_dc }
    end

    def roll_damage(attacker, weapon)
      base = DungeonMaster::Rolls::CombatDice.roll_damage_expression(weapon[:damage].to_s)
      total = [base + str_mod(attacker), 1].max
      { total: total, type: weapon[:damage_type] }
    end

    def apply_damage_to(sheet, damage)
      hp_before = sheet.hp.to_i
      hp_after = hp_before
      dropped = false

      if damage&.fetch(:total, nil)
        hp_after = (hp_before - damage[:total]).clamp(0, sheet.max_hp.to_i)
        sheet.update!(hp: hp_after)
        dropped = hp_after <= 0
      end

      { hp_before: hp_before, hp_after: hp_after, dropped: dropped }
    end

    # @param actors [Hash] attacker, target_sheet, target_kind
    def build_summary(actors:, weapon:, attack_roll:, damage:, target_state:)
      target_label = target_sheet_label(actors[:target_sheet], actors[:target_kind])
      {
        attacker_name: actors[:attacker].name,
        target_name: target_label,
        weapon_label: weapon[:label],
        message: human_message(
          actors: actors, weapon: weapon, attack_roll: attack_roll,
          damage: damage, target_state: target_state
        )
      }
    end

    def target_sheet_label(sheet, kind)
      kind == :player ? 'You' : sheet.name.to_s
    end

    def weapon_with_dice?(weapon)
      weapon.is_a?(Hash) && (weapon['damage_dice'] || weapon[:damage_dice]).to_s.match?(/\d+d\d+/)
    end

    def weapon_payload(weapon)
      {
        label: weapon['name'].presence || weapon[:name].presence || 'weapon',
        damage: weapon['damage_dice'] || weapon[:damage_dice],
        damage_type: weapon['damage_type'] || weapon[:damage_type]
      }
    end

    # @param actors [Hash] attacker, target_sheet, target_kind
    def human_message(actors:, weapon:, attack_roll:, damage:, target_state:)
      target_label = target_sheet_label(actors[:target_sheet], actors[:target_kind])
      core = attack_core_phrase(actors[:attacker], target_label, weapon, attack_roll)
      return "#{core}." unless attack_roll[:hit] && damage

      damage_phrase = damage_phrase_for(damage)
      tail = drop_phrase_for(actors[:target_kind], target_state[:dropped], target_label)
      "#{core} for #{damage_phrase} damage#{tail}."
    end

    def attack_core_phrase(attacker, target_label, weapon, attack_roll)
      verb = attack_roll[:hit] ? 'hits' : 'misses'
      "#{attacker.name} (#{weapon[:label]}) vs #{target_label}: " \
        "#{attack_roll[:total]} vs AC #{attack_roll[:defense_dc]} — #{verb}"
    end

    def damage_phrase_for(damage)
      type = damage[:type]
      type.present? ? "#{damage[:total]} #{type}" : damage[:total].to_s
    end

    def drop_phrase_for(target_kind, dropped, target_label)
      return '' unless dropped

      return ', you fall unconscious!' if target_kind == :player

      ", dropping #{target_label}"
    end
  end
end
