# frozen_string_literal: true

module PlayerTurn
  class CastRoster
    attr_reader :entries

    def self.empty
      new(entries: [])
    end

    def self.from_adventure_npcs(npcs)
      entries = Array(npcs).filter_map do |npc|
        next nil unless npc.respond_to?(:id) && npc.respond_to?(:actor_sheet_id)

        CastRosterEntry.new(
          adventure_npc_id:  npc.id,
          actor_sheet_id: npc.actor_sheet_id,
          name:              npc.name,
          attitude:          npc.attitude,
          location_name:     npc.location_name,
        )
      end
      new(entries: entries)
    end

    def initialize(entries:)
      @entries = Array(entries).freeze
    end

    def empty?
      @entries.empty?
    end

    def size
      @entries.size
    end

    def find_by_actor_sheet_id(id)
      id = id.to_i
      @entries.find { |e| e.actor_sheet_id.to_i == id }
    end

    def hostile_entries
      @entries.select(&:hostile?)
    end

    # @return [Array<String>]
    def prompt_lines
      @entries.map do |entry|
        loc = entry.location_name.to_s.strip
        loc_part = loc.empty? ? "" : " — at #{loc}"
        "[id=#{entry.actor_sheet_id}] #{entry.name} (#{entry.attitude})#{loc_part}"
      end
    end

    def to_h
      { entries: @entries.map(&:to_h) }
    end
  end
end
