# frozen_string_literal: true

module Transformers
  module Transformers::CoercedMutationArray
    module_function

    def coerce(raw, field:, log: nil)
      return [] if raw.nil?

      unless raw.is_a?(Array)
        PlayerTurn::LogWarn.emit(log, "[mutations] #{field} must be Array or nil (#{raw.class} ignored)")
        return []
      end

      raw
    end
  end
end
