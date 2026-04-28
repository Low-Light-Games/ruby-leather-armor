# frozen_string_literal: true

module DungeonMaster
  module Steps
    module RollRequest
      # Value object for the RollRequest prompt template. Holds only the
      # data the prompt actually reads, so callers cannot accidentally
      # smuggle the character sheet, micro-contexts, or domain partials
      # into the request — those are the explicit cuts that justify this
      # step's existence vs. the legacy beacon→mech_eval→roll_qualifier
      # chain.
      class Context
        attr_reader :intent, :recent_beats, :relevant_rules

        def initialize(intent:, recent_beats:, relevant_rules:)
          @intent          = intent
          @recent_beats    = Array(recent_beats)
          @relevant_rules  = Array(relevant_rules)
        end
      end
    end
  end
end
