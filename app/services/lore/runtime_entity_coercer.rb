# frozen_string_literal: true

module Lore
  class RuntimeEntityCoercer
    VALID_ATTITUDES = AdventureNpc::ATTITUDES.to_set.freeze

    def self.build_npc_records(raw_npcs)
      raw_npcs.filter_map { |hash| build_npc(hash) }
    end

    def self.build_location_records(raw_locations)
      raw_locations.filter_map { |hash| build_location(hash) }
    end

    def self.build_npc(hash)
      name = hash["name"].to_s.strip.squish
      return nil if name.blank?

      NpcRecord.new(
        name:           name,
        description:    hash["description"].to_s,
        attitude:       validated_attitude(hash["attitude"]),
        location_name:  hash["location_name"]&.to_s.presence,
        story_npc_id:   nil,
        actor_sheet_id: nil,
      )
    end

    def self.build_location(hash)
      name = hash["name"].to_s.strip.squish
      return nil if name.blank?

      LocationRecord.new(
        name:              name,
        description:       hash["description"].to_s,
        x:                 0,
        y:                 0,
        story_location_id: nil,
      )
    end

    def self.validated_attitude(raw)
      val = raw.to_s.strip.downcase
      VALID_ATTITUDES.include?(val) ? val : "indifferent"
    end

    private_class_method :build_npc, :build_location, :validated_attitude
  end
end
