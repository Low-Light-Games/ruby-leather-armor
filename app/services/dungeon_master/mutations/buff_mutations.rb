# frozen_string_literal: true

module DungeonMaster
  module Mutations
    class BuffMutations
      def initialize(adventure:, log:)
        @adventure = adventure
        @log = log
      end

      def apply(sheet:, buff_lists:)
        return false unless sheet.respond_to?(:active_buffs)

        rows = BuffMutationLists.active_buff_rows_from_sheet(sheet, log: @log)
        class_ability_ids = class_ability_ids_for_buff_adds(sheet, buff_lists.additions)

        changed = apply_removals!(rows, buff_lists.removals)
        changed = apply_additions!(rows, buff_lists.additions, sheet, class_ability_ids) || changed

        if changed
          sheet.update!(active_buffs: rows)
          summary = rows.map { |r| "#{r['source']}:#{r['source_type']}" }.join(", ")
          @log.log!(:info, "[buffs] updated active_buffs on sheet #{sheet.id}: #{summary}")
        end

        changed
      end

      private

      def class_ability_ids_for_buff_adds(sheet, additions)
        wants = additions.any? { |row| row.is_a?(Hash) && row["source_type"].to_s == "class_ability" }
        return unless wants && sheet.respond_to?(:class_ability_definitions)

        sheet.class_ability_definitions.pluck(:id).map(&:to_s)
      end

      def apply_removals!(rows, removals)
        changed = false
        removals.each do |raw_spec|
          changed = remove_rows_for_spec!(rows, raw_spec) || changed
        end
        changed
      end

      def remove_rows_for_spec!(rows, raw_spec)
        unless raw_spec.is_a?(Hash)
          @log&.log!(:warn, "[buffs] buffs_remove entry must be a Hash with id and source_type — skipped #{raw_spec.inspect}")
          return false
        end
        spec = raw_spec.deep_stringify_keys
        source_id = spec["id"].presence || spec["source"].presence
        source_type = spec["source_type"].presence
        unless source_id && source_type
          @log&.log!(:warn, "[buffs] buffs_remove entry missing id or source_type — skipped #{spec.inspect}")
          return false
        end
        before = rows.size
        rows.reject! do |row|
          next false unless row["source"].to_s == source_id.to_s

          stored_type = row["source_type"].to_s
          stored_type == source_type.to_s || stored_type.empty?
        end
        rows.size != before
      end

      def apply_additions!(rows, additions, sheet, class_ability_ids)
        changed = false
        additions.each do |raw_row|
          changed = merge_resolved_add_row!(rows, raw_row, sheet, class_ability_ids) || changed
        end
        changed
      end

      def merge_resolved_add_row!(rows, raw_row, sheet, class_ability_ids)
        return false unless raw_row.is_a?(Hash)

        row = raw_row.deep_stringify_keys
        source_id = row["id"]
        source_type = row["source_type"]
        return false unless source_id.present? && source_type.present?

        resolved = Utilities::ActiveBuffResolver.resolve(
          source_id: source_id,
          source_type: source_type,
          adventure: @adventure,
          sheet: sheet,
          log: @log,
          allowed_class_ability_ids: class_ability_ids,
          buffs_add_entry: row
        )
        return false if resolved.empty?

        rows.reject! do |existing|
          next false unless existing["source"].to_s == source_id.to_s

          existing_type = existing["source_type"].to_s
          existing_type.empty? || existing_type == source_type.to_s
        end
        rows.concat(resolved)
        true
      end
    end
  end
end
