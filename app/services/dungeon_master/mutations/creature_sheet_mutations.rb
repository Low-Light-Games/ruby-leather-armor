# frozen_string_literal: true

module DungeonMaster
  module Mutations
    class CreatureSheetMutations
      def initialize(adventure:, log:)
        @adventure = adventure
        @log = log
      end

      def call(creature_sheet_muts)
        CoercedMutationArray.coerce(creature_sheet_muts, field: "npcs", log: @log).each do |mut|
          mut = mut.deep_symbolize_keys if mut.is_a?(Hash)
          sheet = lookup_target_sheet(mut)
          next unless sheet

          hp_change = mut[:hp_change]
          if hp_change.to_i != 0
            new_hp = (sheet.hp + hp_change.to_i).clamp(0, sheet.max_hp)
            sheet.update!(hp: new_hp)
          end

          attitude = mut[:attitude_change]
          if attitude.is_a?(Hash)
            new_attitude = attitude[:to]
            sheet.update!(attitude: new_attitude) if new_attitude && CreatureSheet::ATTITUDES.include?(new_attitude)
          end

          conditions_changed = Conditions.apply(
            sheet: sheet,
            add: mut[:conditions_add],
            remove: mut[:conditions_remove],
            log: @log
          )
          sheet.recompute_derived_stats! if conditions_changed
        end
      end

      private

      def lookup_target_sheet(mut)
        sid = mut[:creature_sheet_id]
        if sid.present?
          @adventure.creature_sheets.find_by(id: sid.to_i)
        elsif mut[:name].present?
          @adventure.creature_sheets.find_by(name: mut[:name].to_s)
        end
      end
    end
  end
end
