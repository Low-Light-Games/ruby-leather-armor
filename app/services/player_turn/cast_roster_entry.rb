# frozen_string_literal: true

module PlayerTurn
  # One row of `PlayerTurn::CastRoster` — a thin projection of an
  # `AdventureNpc` that downstream steps target by integer id. The keys
  # are the contract that `roll_request.text.erb` and
  # `Encounters::Warmaster.persist_combat_from_cast_roster!` read, so
  # per `.cursor/rules/no-ad-hoc-structures.mdc` it lives as a named
  # class rather than an inline Struct.
  class CastRosterEntry
    attr_reader :adventure_npc_id, :actor_sheet_id, :name, :attitude, :location_name

    def initialize(adventure_npc_id:, actor_sheet_id:, name:, attitude:, location_name: nil)
      @adventure_npc_id  = adventure_npc_id
      @actor_sheet_id = actor_sheet_id
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
        actor_sheet_id: actor_sheet_id,
        name:              name,
        attitude:          attitude,
        location_name:     location_name,
      }
    end
  end
end
