# frozen_string_literal: true

module PlayerTurn
  class Engine
    module Phases
      class OocGate
        def self.call(pipeline_engine, state)
          return { halt: false } unless state[:intent_type] == "ooc"

          response = pipeline_engine.send(:run_ooc_responder, state.fetch(:clean_input))
          {
            halt: true,
            result: { action: :ooc_response, response: response }
          }
        end
      end
    end
  end
end
