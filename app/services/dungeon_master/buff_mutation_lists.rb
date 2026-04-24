# frozen_string_literal: true

module DungeonMaster
  # buffs_add / buffs_remove from a player mutation: normalized lists and sheet row snapshot.
  class BuffMutationLists
    def self.from_payload(buffs_add:, buffs_remove:, log:)
      new(
        additions: stringify_entry_hashes(CoercedMutationArray.coerce(buffs_add, field: "buffs_add", log: log)),
        removals: stringify_entry_hashes(CoercedMutationArray.coerce(buffs_remove, field: "buffs_remove", log: log))
      )
    end

    def self.active_buff_rows_from_sheet(sheet, log:)
      raw = sheet.active_buffs
      return [] if raw.nil?

      unless raw.is_a?(Array)
        Utilities::PipelineWarn.emit(log, "[buffs] sheet.active_buffs must be Array or nil (#{raw.class} treated as empty)")
        return []
      end

      raw.map(&:deep_stringify_keys)
    end

    def initialize(additions:, removals:)
      @additions = additions
      @removals = removals
    end

    attr_reader :additions, :removals

    def any_additions?
      @additions.any?
    end

    def any_removals?
      @removals.any?
    end

    def self.stringify_entry_hashes(entries)
      entries.map { |row| row.is_a?(Hash) ? row.deep_stringify_keys : row }
    end
    private_class_method :stringify_entry_hashes
  end
end
