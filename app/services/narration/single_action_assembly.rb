# frozen_string_literal: true

module Narration
  class SingleActionAssembly
    def self.call(pipeline_engine:, result:)
      loop = pipeline_engine.loop
      outcome = loop&.get("pipeline_outcome")

      prior = if pipeline_engine.send(:action_queue_continuity?)
                AdventureLoop.prior_pipeline_outcomes_before(
                  registry_entry_uuid: pipeline_engine.log.registry_entry_uuid,
                  current_loop: loop)
              else
                []
              end

      player_death         = result[:player_death]
      player_incapacitated = result[:player_incapacitated]
      death_type = if player_death
                     :player_death
                   elsif player_incapacitated
                     :player_incapacitated
                   end

      ctx = PlayerTurn::Context.new(
        combined_seed: outcome,
        player_action: loop&.player_intent,
        prior_outcomes: prior,
        death_type: death_type
      )

      extra = {}
      extra[:player_death]         = true if player_death
      extra[:player_incapacitated] = true if player_incapacitated

      action_outcomes = [result[:action_outcome]].compact + Array(result[:mutation_lines])
      extra[:action_outcomes] = action_outcomes if action_outcomes.any?

      NarrationPhaseInputs.new(
        intent: result[:intent],
        pipeline_context: ctx,
        mutations: result[:mutations],
        extra: extra
      )
    end
  end
end
