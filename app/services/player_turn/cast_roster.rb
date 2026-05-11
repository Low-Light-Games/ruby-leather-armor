# frozen_string_literal: true

module PlayerTurn
  # Snapshot of the cast in scope for one player action — produced by
  # `Steps::CastResolve` (which delegates to `Encounters::CastResolver`)
  # and consumed downstream by `Steps::RollRequest`, `Steps::Stagehand`,
  # and `Encounters::Warmaster.persist_pending_combat!`.
  #
  # Each `CastRosterEntry` is a thin projection of an `AdventureNpc` row
  # with its linked `creature_sheet_id` — the integer ID is the only
  # thing downstream code or prompts ever need to refer to a creature.
  # Names live alongside the ID strictly for prompt rendering and
  # human-readable logs.
  class CastRoster
    attr_reader :entries

    def self.empty
      new(entries: [])
    end

    def self.from_adventure_npcs(npcs)
      entries = Array(npcs).filter_map do |npc|
        next nil unless npc.respond_to?(:id) && npc.respond_to?(:creature_sheet_id)

        CastRosterEntry.new(
          adventure_npc_id:  npc.id,
          creature_sheet_id: npc.creature_sheet_id,
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

    def find_by_creature_sheet_id(id)
      id = id.to_i
      @entries.find { |e| e.creature_sheet_id.to_i == id }
    end

    def hostile_entries
      @entries.select(&:hostile?)
    end

    # Prompt-facing single-line summary per entry. Consumed by
    # `roll_request.text.erb` to expose the roster to the AI.
    def prompt_lines
      @entries.map do |entry|
        loc = entry.location_name.to_s.strip
        loc_part = loc.empty? ? "" : " — at #{loc}"
        "[id=#{entry.creature_sheet_id}] #{entry.name} (#{entry.attitude})#{loc_part}"
      end
    end

    def to_h
      { entries: @entries.map(&:to_h) }
    end
  end
end
