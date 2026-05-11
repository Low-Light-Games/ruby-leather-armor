# frozen_string_literal: true

module PlayerTurn
  # One row of `PlayerTurn::CastRoster` — a thin projection of an
  # `AdventureNpc` that downstream steps target by integer id.
  #
  # Per `.cursor/rules/no-ad-hoc-structures.mdc` this is a real class
  # rather than a `Struct.new(...)` inside the parent file: the keys
  # are the contract that `roll_request.text.erb` (commit 11) and
  # `Encounters::Warmaster.persist_pending_combat!` (commit 13) read,
  # and a class header documents that contract once.
  class CastRosterEntry
    attr_reader :adventure_npc_id, :creature_sheet_id, :name, :attitude, :location_name

    def initialize(adventure_npc_id:, creature_sheet_id:, name:, attitude:, location_name: nil)
      @adventure_npc_id  = adventure_npc_id
      @creature_sheet_id = creature_sheet_id
      @name              = name
      @attitude          = attitude
      @location_name     = location_name
    end

    def hostile?
      attitude.to_s == "unfriendly"
    end

    def to_h
      {
        adventure_npc_id:  adventure_npc_id,
        creature_sheet_id: creature_sheet_id,
        name:              name,
        attitude:          attitude,
        location_name:     location_name,
      }
    end
  end
end
