# frozen_string_literal: true

module Combat
  # Validation/lookup error raised by Combat::PlayerActionResolver and
  # the per-kind resolver concerns under Combat::Resolvers::*. Carries
  # a stable `:code` symbol so the controller can map errors to UI
  # feedback without sniffing message strings.
  class ResolverError < StandardError
    attr_reader :code

    def initialize(message, code: :resolver_error)
      super(message)
      @code = code
    end
  end
end
