# frozen_string_literal: true

module Combat
  # Resolves a single deterministic NPC attack against a target sheet.
  # Used by PR-D's AoO trigger and (later) PR-F's NPC behavior engine.
  # Pure server-side dice — clients never roll for NPCs.
  module NpcAttackResolver
    DEFAULT_NATURAL_DAMAGE = '1d4'

    Outcome = Struct.new(:attacker_name, :target_name, :hit, :natural, :total, :defense_dc,
                         :damage_total, :damage_type, :target_hp_before, :target_hp_after,
                         :target_dropped, :weapon_label, :message, keyword_init: true) do
      def to_h
        super.transform_keys(&:to_s)
      end
    end

    module_function

    def call(attacker:, target_sheet:, target_kind:)
      attack_bonus = attack_bonus_for(attacker)
      defense_dc = (target_sheet.derived_stats || {}).then { |s| (s['ac'] || s[:ac]).to_i }
      natural = DungeonMaster::Rolls::CombatDice.roll_d20
      total = natural + attack_bonus
      hit = (total >= defense_dc || natural == 20) && natural != 1

      weapon = primary_weapon_for(attacker)
      damage_total = nil
      hp_before = target_sheet.hp.to_i
      hp_after = hp_before
      dropped = false

      if hit
        base = DungeonMaster::Rolls::CombatDice.roll_damage_expression(weapon[:damage].to_s)
        damage_total = [base + str_mod(attacker), 1].max
        hp_after = apply_damage(target_sheet, target_kind, damage_total)
        dropped = hp_after <= 0
      end

      Outcome.new(
        attacker_name: attacker.name, target_name: target_sheet_label(target_sheet, target_kind),
        hit: hit, natural: natural, total: total, defense_dc: defense_dc,
        damage_total: damage_total, damage_type: weapon[:damage_type],
        target_hp_before: hp_before, target_hp_after: hp_after, target_dropped: dropped,
        weapon_label: weapon[:label],
        message: human_message(attacker, target_sheet, target_kind, weapon, hit, total, defense_dc, damage_total, dropped)
      )
    end

    def attack_bonus_for(creature)
      stats = creature.derived_stats || {}
      bonus = stats['melee_attack'] || stats[:melee_attack] || stats['bab'] || stats[:bab]
      bonus.to_i
    end

    def str_mod(creature)
      mods = (creature.derived_stats || {})['mods'] || {}
      val = mods['strength']
      return val.to_i if val

      ((creature.strength.to_i - 10) / 2).floor
    end

    def primary_weapon_for(creature)
      first = Array(creature.equipped_weapons).find do |w|
        w.is_a?(Hash) && (w['damage_dice'] || w[:damage_dice]).to_s.match?(/\d+d\d+/)
      end
      if first
        {
          label: first['name'].presence || first[:name].presence || 'weapon',
          damage: first['damage_dice'] || first[:damage_dice],
          damage_type: first['damage_type'] || first[:damage_type]
        }
      else
        { label: 'natural attack', damage: DEFAULT_NATURAL_DAMAGE, damage_type: nil }
      end
    end

    def apply_damage(sheet, target_kind, dmg)
      max = sheet.max_hp.to_i
      floor = target_kind == :player ? 0 : 0
      new_hp = (sheet.hp.to_i - dmg.to_i).clamp(floor, max)
      sheet.update!(hp: new_hp)
      new_hp
    end

    def target_sheet_label(sheet, kind)
      kind == :player ? 'You' : sheet.name.to_s
    end

    def human_message(attacker, target_sheet, target_kind, weapon, hit, total, defense_dc, damage_total, dropped)
      target_label = target_sheet_label(target_sheet, target_kind)
      verb = hit ? 'hits' : 'misses'
      core = "#{attacker.name} (#{weapon[:label]}) vs #{target_label}: #{total} vs AC #{defense_dc} — #{verb}"
      return "#{core}." unless hit && damage_total

      damage_phrase = "#{damage_total}#{" #{weapon[:damage_type]}" if weapon[:damage_type].present?}"
      tail = dropped && target_kind != :player ? ", dropping #{target_label}" : ''
      tail = ", you fall unconscious!" if dropped && target_kind == :player
      "#{core} for #{damage_phrase} damage#{tail}."
    end
  end
end
