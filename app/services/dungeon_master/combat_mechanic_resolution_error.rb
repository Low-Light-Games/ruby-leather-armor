# frozen_string_literal: true

module DungeonMaster
  # Raised when {CombatMechanicResolution} cannot resolve combat mech-eval JSON.
  class CombatMechanicResolutionError < StandardError
    attr_reader :code

    def initialize(message, code: :resolution_failed)
      @code = code
      super(message)
    end
  end
end
