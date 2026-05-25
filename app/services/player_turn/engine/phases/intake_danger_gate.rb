# frozen_string_literal: true

module PlayerTurn
  class Engine
    module Phases
      class IntakeDangerGate
        # @param state [Hash] must include :player_input
        # @return [Hash] :halt => true, :result => terminal hash — or —
        def self.call(pipeline_engine, state)
          intake_result = pipeline_engine.send(:run_intake, state.fetch(:player_input))

          if intake_result[:danger_score] >= pipeline_engine.config.danger_threshold
            pipeline_engine.log.play_log!("intake_rejection",
              "Rejected (danger: #{intake_result[:danger_score]}): #{intake_result[:reason]}")
            return {
              halt: true,
              result: { action: :rejected, reason: intake_result[:reason], danger: intake_result[:danger_score] }
            }
          end

          { halt: false,
            clean_input: intake_result[:sanitized_input],
            intake_result: intake_result,
            intent_type: intake_result[:intent_type],
            target_npc: intake_result[:target_npc] }
        end
      end
    end
  end
end
