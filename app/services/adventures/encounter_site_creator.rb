# frozen_string_literal: true

module Adventures
  module EncounterSiteCreator
    module_function

    def create!(adventure:, from:, to:, fraction:, ai:, log:)
      raise ArgumentError, "from is required" unless from

      raise ArgumentError, "to is required" unless to

      f = fraction.to_f.clamp(0.0, 1.0)
      x = from.x.to_f + ((to.x.to_f - from.x.to_f) * f)
      y = from.y.to_f + ((to.y.to_f - from.y.to_f) * f)

      record = Lore::LocationRecord.new(
        name:        next_encounter_site_name(adventure),
        description: build_description(from: from, to: to, fraction: f),
        x:           x,
        y:           y,
      )

      created = Lore::ApplyLocations.call(
        adventure:        adventure,
        log:              log,
        ai:               ai,
        location_records: [record],
        source:           "encounter",
      )
      created.first
    end

    def next_encounter_site_name(adventure)
      existing = AdventureLocation.where(adventure_id: adventure.id, source: "encounter").count
      "Encounter site #{existing + 1}"
    end

    def build_description(from:, to:, fraction:)
      pct = (fraction * 100).round
      "On the road from #{from.name} to #{to.name}, roughly #{pct}% of the way."
    end
  end
end
