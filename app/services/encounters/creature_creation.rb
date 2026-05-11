# frozen_string_literal: true

module Encounters
  # Single public creature-instantiation surface. Used by:
  #   * Encounters::CastResolver       — turning AI-named creatures into sheets
  #   * Lore::SeedFromAdventure        — adventure-creation clones for StoryNpcs
  #   * Encounters::EncounterWarmasterBridge — Harbinger random encounters
  #   * Encounters::Warmaster          — the bestiary path (delegates here)
  #
  # All callers reach a CreatureSheet through `from_bestiary`. There is no
  # AI generator on the per-turn hot path — story NPCs are statted at
  # authoring time (Authoring::AuthorStoryNpcSheet) and cold-spawned
  # creatures fall back deterministically to a `default_for_type` BestiaryEntry.
  module CreatureCreation
    MIN_COUNT = 1
    MAX_COUNT = 12

    # @param adventure [Adventure]
    # @param bestiary_entry [BestiaryEntry]
    # @param display_name [String, nil]
    # @param count [Integer] clamped to [MIN_COUNT, MAX_COUNT]
    # @return [Array<CreatureSheet>]
    def self.from_bestiary(adventure:, bestiary_entry:, display_name: nil, count: 1)
      raise ArgumentError, "bestiary_entry required" if bestiary_entry.nil?

      raise ArgumentError, "adventure required"      if adventure.nil?

      effective_count = count.to_i.clamp(MIN_COUNT, MAX_COUNT)
      base_name = display_name.to_s.strip.presence || bestiary_entry.name

      Array.new(effective_count) do |idx|
        instance_name = effective_count > 1 ? "#{base_name} #{idx + 1}" : base_name
        hp_value = roll_hp(bestiary_entry.hp_formula)

        sheet = adventure.creature_sheets.create!(
          bestiary_entry.to_creature_sheet_attrs(display_name: instance_name).merge(
            hp:     hp_value,
            max_hp: hp_value,
            origin: "bestiary"
          )
        )
        sheet.recompute_derived_stats!
        sheet
      end
    end

    # @param formula [String, Array<String>] PF1e dice notation
    # @return [Integer]
    def self.roll_hp(formula)
      formula = Array(formula).join if formula.is_a?(Array)
      return 10 if formula.to_s.strip.empty?

      if formula.to_s =~ /(\d+)d(\d+)([+-]\d+)?/
        count, die, mod = $1.to_i, $2.to_i, ($3 || 0).to_i
        count.times.sum { rand(1..die) } + mod
      else
        formula.to_i.nonzero? || 10
      end
    end
  end
end
