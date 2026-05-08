# frozen_string_literal: true

module Combat
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
