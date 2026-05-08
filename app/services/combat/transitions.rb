# frozen_string_literal: true

module Combat
  module Transitions
    START_VALUES = %w[combat_started social_to_combat].freeze

    module_function

    def start?(transition)
      START_VALUES.include?(transition.to_s)
    end
  end
end
