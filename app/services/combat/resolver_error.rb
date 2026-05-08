# frozen_string_literal: true

module Combat
  class ResolverError < StandardError
    attr_reader :code

    def initialize(message, code: :resolver_error)
      super(message)
      @code = code
    end
  end
end
