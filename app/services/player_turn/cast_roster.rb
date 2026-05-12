# frozen_string_literal: true

module PlayerTurn
  class CastRoster
    attr_reader :members

    def self.empty
      new(members: [])
    end

    def self.from_adventure_npcs(npcs)
      members = Array(npcs).filter_map do |npc|
        next nil unless npc.respond_to?(:id) && npc.respond_to?(:actor_sheet_id)

        CastMember.new(
          adventure_npc_id:  npc.id,
          actor_sheet_id:    npc.actor_sheet_id,
          name:              npc.name,
          attitude:          npc.attitude,
          location_name:     npc.location_name,
        )
      end
      new(members: members)
    end

    def initialize(members:)
      @members = Array(members).freeze
    end

    def empty?
      @members.empty?
    end

    def size
      @members.size
    end

    def find_by_actor_sheet_id(id)
      id = id.to_i
      @members.find { |m| m.actor_sheet_id.to_i == id }
    end

    def hostile_members
      @members.select(&:hostile?)
    end

    # @return [Array<String>]
    def prompt_lines
      @members.map do |member|
        location_name = member.location_name.to_s.strip
        location_suffix = location_name.empty? ? "" : " — at #{location_name}"
        "[id=#{member.actor_sheet_id}] #{member.name} (#{member.attitude})#{location_suffix}"
      end
    end

    def to_h
      { members: @members.map(&:to_h) }
    end
  end
end
