# frozen_string_literal: true

module Battlefield
  class CombatContextPayload
    def initialize(base_data:, battlefield_reference:, action_economy_builder:)
      @base_data = base_data.deep_stringify_keys
      @battlefield_reference = battlefield_reference
      @action_economy_builder = action_economy_builder
    end

    def to_h
      payload = @base_data.deep_dup
      payload["battlefield_ref"] = @battlefield_reference.to_h
      payload["action_economy"] ||= @action_economy_builder.call(payload)
      payload
    end
  end
end
