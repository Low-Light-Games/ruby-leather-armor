# frozen_string_literal: true

module Combat
  class MechanicResolutionError < StandardError
    attr_reader :code

    def initialize(message, code: :resolution_failed)
      @code = code
      super(message)
    end
  end
end
