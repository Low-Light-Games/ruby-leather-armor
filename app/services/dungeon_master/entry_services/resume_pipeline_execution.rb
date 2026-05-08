# frozen_string_literal: true

module DungeonMaster
  module EntryServices
    class ResumePipelineExecution
      def initialize(runtime:)
        @runtime = runtime
      end

      def call(player_message_id:)
        runtime.enforce_pipeline_policy!
        runtime.log.player_message_id = player_message_id
        result = yield
        runtime.messenger.messages_for(result)
      rescue DungeonMaster::UsageLimitExceeded => e
        runtime.messenger.usage_limit_rejection_messages(e)
      rescue Ai::Error, StandardError => e
        runtime.messenger.pipeline_exception_messages(e)
      end

      private

      attr_reader :runtime
    end
  end
end
