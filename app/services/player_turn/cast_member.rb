# frozen_string_literal: true

module PlayerTurn
  class CastMember
    attr_reader :adventure_npc_id, :actor_sheet_id, :name, :attitude, :location_name

    def initialize(adventure_npc_id:, actor_sheet_id:, name:, attitude:, location_name: nil)
      @adventure_npc_id  = adventure_npc_id
      @actor_sheet_id    = actor_sheet_id
      @name              = name
      @attitude          = attitude
      @location_name     = location_name
    end

    def hostile?
      %w[unfriendly hostile].include?(attitude.to_s)
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
