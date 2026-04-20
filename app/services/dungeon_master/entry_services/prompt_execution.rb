# frozen_string_literal: true

module DungeonMaster
  module EntryServices
    class PromptExecution
      def initialize(runtime:)
        @runtime = runtime
      end

      def call(player_input:, player_message_id:, prompt_mode: nil)
        runtime.enforce_pipeline_policy!
        runtime.log.log_abandoned_pipeline_if_needed!
        DungeonMaster::Rolls::AdventureMechanicalState.auto_finalize_pending_initiative!(
          adventure: runtime.adventure,
          sheet: runtime.sheet,
          log: runtime.log
        )

        moderation_result = moderate_player_input(player_input)
        return moderation_result if moderation_result

        runtime.log.player_message_id = player_message_id
        runtime.log.start_registry_entry!(player_input)
        runtime.ensure_run_pipeline!

        result = DungeonMaster::PipelineTiming.run(runtime.log) do
          runtime.pipeline_engine.run_prompt(player_input, mode: prompt_mode)
        end
        runtime.messenger.messages_for(result)
      rescue DungeonMaster::UsageLimitExceeded => e
        runtime.messenger.usage_limit_rejection_messages(e)
      rescue DungeonMaster::SanitizationRejected => e
        runtime.messenger.sanitization_failure_messages(e)
      rescue DungeonMaster::AiError, StandardError => e
        runtime.messenger.pipeline_exception_messages(e)
      end

      private

      attr_reader :runtime

      def moderate_player_input(player_input)
        if runtime.user&.trusted?
          ModerationCheckJob.perform_later(runtime.user.id, player_input)
          return nil
        end

        moderation = DungeonMaster::ModerationService.call(player_input, user: runtime.user)
        return nil unless moderation.flagged?

        [runtime.messenger.persist_message(
          role: "dm",
          content: moderation.response_text,
          message_type: "moderation_flagged"
        )]
      end
    end
  end
end
