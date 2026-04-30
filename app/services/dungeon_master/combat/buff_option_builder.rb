# frozen_string_literal: true

module DungeonMaster
  module Combat
    # Builds combat HUD self-buff options from the player's spellbook.
    class BuffOptionBuilder < SpellOptionBuilderBase
      SELF_BUFF_RANGES = %w[personal touch].freeze
      BUFF_EFFECT_TYPES = %w[ac_bonus attack_bonus save_bonus skill_bonus
                             ability_bonus immunity special damage_resistance
                             concealment].freeze
      DAMAGE_OR_HEAL_EFFECT_TYPES = %w[damage healing].freeze

      class << self
        def match?(spell)
          self_buff_range?(spell) &&
            friendly_save?(spell) &&
            !damage_or_healing_effect?(spell) &&
            buff_effects?(spell)
        end

        def option_for(spell, _sheet)
          BuffOption.new(spell)
        end

        def kind_label = 'buff'
        def unknown_code = :unknown_buff_option

        private

        def self_buff_range?(spell)
          range = spell.range.to_s.downcase.strip
          SELF_BUFF_RANGES.any? { |allowed| range == allowed || range.start_with?("#{allowed} ") }
        end

        def friendly_save?(spell)
          save = spell.saving_throw.to_s.downcase.strip
          save.empty? || save == 'none' || save.include?('(harmless)')
        end

        def damage_or_healing_effect?(spell)
          Array(spell.effects).any? { |e| e.is_a?(Hash) && DAMAGE_OR_HEAL_EFFECT_TYPES.include?(e['type'].to_s) }
        end

        def buff_effects?(spell)
          Array(spell.effects).any? { |e| e.is_a?(Hash) && BUFF_EFFECT_TYPES.include?(e['type'].to_s) }
        end
      end
    end
  end
end
