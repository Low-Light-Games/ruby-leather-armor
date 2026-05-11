# frozen_string_literal: true

module PlayerTurn
  module Steps
    module RollRequest
      class Context
        attr_reader :intent, :scene_retrieval, :relevant_rules, :current_location_name

        def initialize(intent:, scene_retrieval:, relevant_rules:, current_location_name: nil)
          @intent                 = intent
          @scene_retrieval        = scene_retrieval
          @relevant_rules         = Array(relevant_rules)
          @current_location_name  = current_location_name
        end
      end
    end
  end
end
