# frozen_string_literal: true

module DungeonMaster
  module Mutations
    class ActionEconomySync
      def self.apply!(mutations, adventure:, log:)
        delta = mutations[:action_economy_delta]
        return if delta.blank?

        ctx = adventure.combat_context
        return unless ctx.is_a?(Hash)

        econ = ctx["action_economy"] || ctx[:action_economy]
        merged_econ = Battlefield::ActionEconomy.apply_delta!(econ, delta)
        new_ctx = ctx.deep_stringify_keys.merge("action_economy" => merged_econ)
        adventure.update!(combat_context: new_ctx)
      rescue ArgumentError => e
        log.log!(:warn, "[action_economy_delta] rejected: #{e.message}")
        raise AiError, "Invalid action economy for this turn: #{e.message}"
      end
    end
  end
end
