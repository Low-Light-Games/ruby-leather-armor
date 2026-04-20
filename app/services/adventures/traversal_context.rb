# frozen_string_literal: true

module Adventures
  class TraversalContext
    attr_reader :start_location

    def initialize(start_location:)
      @start_location = start_location
    end

    def to_h
      return {} unless start_location

      context = {
        "current_location" => start_location.name,
        "scene" => start_location.description
      }

      exits = start_location.neighbors.pluck(:name)
      context["exits"] = exits if exits.any?
      context
    end
  end
end
