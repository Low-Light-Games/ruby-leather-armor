# frozen_string_literal: true

module PlayerTurn
  module Steps
    module Loremaster
      class Inputs
        attr_reader :what_happened, :active_facts

        def initialize(what_happened:, active_facts:)
          @what_happened = what_happened
          @active_facts  = active_facts
          freeze
        end
      end
    end
  end
end
