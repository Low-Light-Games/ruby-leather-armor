# frozen_string_literal: true

module DungeonMaster
  module Combat
    # Shared scaffolding for the per-category spell option builders
    # (BuffOptionBuilder, HealOptionBuilder). Each subclass declares
    # its own `match?` predicate and `option_for(spell)` constructor;
    # the base handles iterating the player's spellbook, gating on
    # the standard action, and the resolve_option_id! lookup.
    class SpellOptionBuilderBase
      class << self
        # @param sheet [AdventureSheet]
        # @param adventure [Adventure]
        # @return [Array<Hash>]
        def call(sheet:, adventure:)
          economy = Battlefield::ActionEconomy::Snapshot.from_combat_context(adventure&.combat_context)
          return [] unless sheet && economy.standard_available?

          sheet.adventure_sheet_spells.includes(:spell_definition).filter_map do |entry|
            spell = entry.spell_definition
            next unless spell && match?(spell)

            option_for(spell, sheet).to_h
          end
        end

        # @param sheet [AdventureSheet]
        # @param adventure [Adventure]
        # @param option_id [String] e.g. "spell:shield"
        # @return [Hash]
        def resolve_option_id!(sheet:, adventure:, option_id:)
          option = call(sheet: sheet, adventure: adventure).find { |o| o[:id] == option_id.to_s }
          return option if option

          raise DungeonMaster::CombatMechanicResolutionError.new(
            "unknown or unavailable #{kind_label} option_id: #{option_id.inspect}",
            code: unknown_code
          )
        end

        # Subclasses override.
        def match?(_spell)
          raise NotImplementedError
        end

        def option_for(_spell, _sheet)
          raise NotImplementedError
        end

        def kind_label
          raise NotImplementedError
        end

        def unknown_code
          raise NotImplementedError
        end
      end
    end
  end
end
