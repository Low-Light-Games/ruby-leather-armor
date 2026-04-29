# frozen_string_literal: true

module Combat
  module Narrator
    # AI-chat invocation params for the combat narrator step. Builds the
    # system prompt from a Narrator::Context, reads max-tokens / model
    # from DmConfig, and emits the keyword-arg hash AiClient#chat
    # consumes via #to_h.
    class StepParams
      STEP_NAME = 'combat_narrator'

      # @param context [Combat::Narrator::Context]
      # @param config [DmConfig]
      def initialize(context:, config:)
        @context = context
        @config = config
      end

      def to_h
        {
          system_prompt: DungeonMaster::PromptRenderer.render('combat_narrator', combat_narrator_context: @context),
          user_message: 'Narrate the round.',
          max_tokens: @config.token_budget_for(STEP_NAME) || Combat::Narrator::DEFAULT_MAX_TOKENS,
          step_name: STEP_NAME,
          model: @config.model_for(STEP_NAME)
        }
      end
    end
  end
end
