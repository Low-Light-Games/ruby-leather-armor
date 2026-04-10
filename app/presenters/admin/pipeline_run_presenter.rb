# frozen_string_literal: true

module Admin
  # Builds the presentation hash for a single pipeline run in the
  # Admin::PlayLogsController#pipelines view.
  #
  # Accepts the raw AR result row (grouped aggregate), the logs for that run,
  # the first player message, and the optional PipelineRegistryEntry record,
  # then derives the human-readable status and assembles the hash.
  class PipelineRunPresenter
    TERMINAL_STEPS = %w[narrate dm_query].freeze
    ERROR_STATUSES = %w[api_error parse_error token_budget_exceeded logging_error].freeze

    # @param run             [ActiveRecord::Result] grouped aggregate row
    # @param logs            [Array<PlayLog>]       all logs for this run in order
    # @param player_message  [AdventureMessage, nil]
    # @param registry_entry  [PipelineRegistryEntry, nil]
    def initialize(run, logs:, player_message:, registry_entry:)
      @run             = run
      @logs            = logs
      @player_message  = player_message
      @registry_entry  = registry_entry
    end

    def as_hash
      {
        registry_entry_uuid: @run.registry_entry_uuid,
        adventure_id:        @run.adventure_id,
        first_at:            @run.first_at,
        last_at:             @run.last_at,
        step_count:          @run.step_count,
        message_content:     @player_message&.content || @logs.first&.player_message_content,
        logs:                @logs,
        status:              resolved_status,
        registry_entry:      @registry_entry,
      }
    end

    private

    def resolved_status
      return @registry_entry.status if @registry_entry

      step_types = @logs.map(&:event_type)
      has_error    = @logs.any? { |l| l.status.in?(ERROR_STATUSES) }
      has_terminal = step_types.any? { |t| TERMINAL_STEPS.include?(t) }

      if has_error && !has_terminal then "errored"
      elsif has_error               then "partial"
      elsif has_terminal            then "complete"
      else                               "incomplete"
      end
    end
  end
end
