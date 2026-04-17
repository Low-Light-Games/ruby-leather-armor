# frozen_string_literal: true

module DungeonMaster
  module Combat
    module AttackOptionBuilder
      MONK_UNARMED_DICE = {
        20 => "2d10",
        16 => "2d8",
        12 => "2d6",
        8 => "1d10",
        4 => "1d8",
        1 => "1d6"
      }.freeze

      class << self
        def call(sheet:, adventure:)
          return [] unless sheet
          return [] unless attack_action_available?(adventure)

          [
            *spell_attack_options(sheet),
            *equipped_weapon_options(sheet),
            unarmed_option_for(sheet)
          ].compact
        end

        def resolve_option_id!(sheet:, adventure:, option_id:)
          option = call(sheet: sheet, adventure: adventure).find { |entry| entry[:id] == option_id.to_s }
          return option if option

          raise DungeonMaster::CombatMechanicResolutionError.new(
            "unknown or unavailable attack_option_id: #{option_id.inspect}",
            code: :unknown_attack_option
          )
        end

        private

        def attack_action_available?(adventure)
          combat_ctx = adventure&.combat_context
          economy = combat_ctx.is_a?(Hash) ? combat_ctx["action_economy"] : nil
          return true unless economy.is_a?(Hash)

          econ = economy.deep_stringify_keys
          truthy?(econ["standard_available"]) && !truthy?(econ["full_round_claimed"])
        end

        def truthy?(value)
          value == true || value.to_s == "true"
        end

        def spell_attack_options(sheet)
          sheet.adventure_sheet_spells.includes(:spell_definition).filter_map do |entry|
            spell = entry.spell_definition
            next unless spell

            build_spell_options(spell)
          end.flatten
        end

        def build_spell_options(spell)
          effect = spell_damage_effect_for(spell)
          return [] unless effect

          attack_mode = spell_attack_mode_for(spell)
          return [] unless attack_mode

          [{
            id: "spell:#{spell.id}",
            label: spell.name,
            attack_mode: attack_mode,
            defense_kind: "touch_ac",
            source_type: "spell",
            source_id: spell.id,
            damage: effect["dice"],
            damage_type: effect["damageType"] || effect["damage_type"],
            action_cost: "standard"
          }.compact]
        end

        def spell_damage_effect_for(spell)
          Array(spell.effects).find do |effect|
            next false unless effect.is_a?(Hash)

            effect["type"].to_s == "damage"
          end
        end

        def spell_attack_mode_for(spell)
          summary = [spell.summary, spell_effect_descriptions(spell)].compact.join(" ").downcase

          if summary.include?("use as touch or ranged touch") ||
             summary.include?("touch attack or throw as ranged touch")
            nil
          elsif summary.match?(/\branged touch attack\b|\branged touch\b/)
            "ranged_touch"
          elsif spell.range.to_s.downcase.start_with?("touch") ||
                summary.match?(/\btouch attack\b|\btouch deals\b/)
            "melee_touch"
          else
            nil
          end
        end

        def spell_effect_descriptions(spell)
          Array(spell.effects).filter_map do |effect|
            next unless effect.is_a?(Hash)

            effect["description"]
          end.join(" ")
        end

        def equipped_weapon_options(sheet)
          sheet.adventure_sheet_items.includes(:item_definition).filter_map do |entry|
            next unless entry.equipped?

            item = entry.item_definition
            next unless item
            next unless %w[weapon shield].include?(item.item_type)
            next if item.damage_dice.blank?

            {
              id: "weapon:#{item.id}",
              label: weapon_label_for(item),
              attack_mode: item.weapon_type == "ranged" ? "ranged" : "melee",
              defense_kind: "full_ac",
              source_type: "weapon",
              source_id: item.id,
              damage: item.damage_dice,
              damage_type: item.damage_type,
              action_cost: "standard"
            }.compact
          end.uniq { |entry| entry[:id] }
        end

        def weapon_label_for(item)
          return "#{item.name} (bash)" if item.item_type == "shield"

          item.name
        end

        def unarmed_option_for(sheet)
          {
            id: "unarmed",
            label: "Unarmed Strike",
            attack_mode: "melee",
            defense_kind: "full_ac",
            source_type: "unarmed",
            damage: unarmed_damage_for(sheet),
            damage_type: "bludgeoning",
            action_cost: "standard"
          }
        end

        def unarmed_damage_for(sheet)
          cls = sheet.character_class.to_s.downcase
          if cls == "monk"
            MONK_UNARMED_DICE.each do |min_level, dice|
              return dice if sheet.level.to_i >= min_level
            end
          end

          "1d3"
        end
      end
    end
  end
end
