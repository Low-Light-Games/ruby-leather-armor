# frozen_string_literal: true

module Combat
  # Per-participant snapshot rendered by the combat HUD's targets list.
  # Wraps a CreatureSheet in the exact shape the frontend expects so the
  # controller doesn't hand-roll a hash literal at the boundary.
  class HostileTarget
    attr_reader :creature

    # @param creature [CreatureSheet]
    def initialize(creature)
      @creature = creature
    end

    def to_h
      {
        creature_sheet_id: creature.id,
        name: creature.name,
        hp: creature.hp,
        max_hp: creature.max_hp,
        dropped: creature.hp.to_i <= 0
      }
    end
  end
end
