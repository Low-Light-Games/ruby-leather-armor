# frozen_string_literal: true

module Lore
  class RuntimeEntityFilter
    def self.filter_npcs(adventure:, raw_npcs:)
      return [] if raw_npcs.empty?

      names_of_all_existing_adventure_npcs = AdventureNpc.for_adventure(adventure)
                                             .pluck(:name).map { |n| normalize(n) }.to_set
      dedup_by_name(raw_npcs.reject { |n| names_of_all_existing_adventure_npcs.include?(normalize(n["name"])) })
    end

    def self.filter_locations(adventure:, raw_locations:)
      return [] if raw_locations.empty?

      names_of_all_existing_adventure_locations = AdventureLocation.for_adventure(adventure)
                                                    .pluck(:name).map { |n| normalize(n) }.to_set
      dedup_by_name(raw_locations.reject { |l| names_of_all_existing_adventure_locations.include?(normalize(l["name"])) })
    end

    def self.dedup_by_name(entries)
      seen = Set.new
      entries.select { |e| seen.add?(normalize(e["name"])) }
    end

    private_class_method :dedup_by_name

    LEADING_ARTICLES = /\A(the|a|an)\s+/i

    def self.normalize(name)
      name.to_s.strip.squish.downcase.sub(LEADING_ARTICLES, "")
    end

    private_class_method :normalize
  end
end
