# frozen_string_literal: true

module Combat
  module Options
    class HealOptionBuilder < SpellOptionBuilderBase
      SELF_HEAL_RANGES = %w[personal touch].freeze

      class << self
        def match?(spell)
          healing_effect?(spell) && self_heal_range?(spell) && friendly_save?(spell)
        end

        def option_for(spell, sheet)
          HealOption.new(spell, sheet)
        end

        def kind_label = 'heal'
        def unknown_code = :unknown_heal_option

        private

        def healing_effect?(spell)
          Array(spell.effects).any? { |e| e.is_a?(Hash) && e['type'].to_s == 'healing' }
        end

        def self_heal_range?(spell)
          range = spell.range.to_s.downcase.strip
          SELF_HEAL_RANGES.any? { |allowed| range == allowed || range.start_with?("#{allowed} ") }
        end

        def friendly_save?(spell)
          save = spell.saving_throw.to_s.downcase.strip
          save.empty? || save == 'none' || save.include?('(harmless)')
        end
      end
    end
  end
end
