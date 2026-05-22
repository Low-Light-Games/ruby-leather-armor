# frozen_string_literal: true

module Lore
  class RuntimeEntityFilter
    def self.filter_npcs(adventure:, raw_npcs:)
      return [] if raw_npcs.empty?

      existing = AdventureNpc.for_adventure(adventure)
                   .pluck(:name).map { |n| normalize(n) }.to_set
      raw_npcs.reject { |n| existing.include?(normalize(n["name"])) }
    end

    def self.filter_locations(adventure:, raw_locations:)
      return [] if raw_locations.empty?

      existing = AdventureLocation.for_adventure(adventure)
                   .pluck(:name).map { |n| normalize(n) }.to_set
      raw_locations.reject { |l| existing.include?(normalize(l["name"])) }
    end

    def self.normalize(name)
      name.to_s.strip.squish.downcase
    end

    private_class_method :normalize
  end
end
