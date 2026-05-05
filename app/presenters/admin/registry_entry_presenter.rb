# frozen_string_literal: true

module Admin
  # Builds the presentation hash for a single PipelineRegistryEntry in the
  # Admin::PlayLogsController#pipelines view.
  #
  # Accepts the grouped SQL aggregate row (summary stats across play logs),
  # the ordered logs for that entry, the triggering player message, and the
  # optional PipelineRegistryEntry record, then derives human-readable status
  # and assembles the hash.
  class RegistryEntryPresenter
    TERMINAL_STEPS = %w[narrate].freeze
    ERROR_STATUSES = %w[api_error parse_error token_budget_exceeded logging_error].freeze

    # @param log_aggregate   [ActiveRecord::Result] grouped aggregate row (first_at, last_at, step_count, …)
    # @param logs            [Array<PlayLog>]       all logs for this entry in order
    # @param player_message  [AdventureMessage, nil]
    # @param registry_entry  [PipelineRegistryEntry, nil]
    def initialize(log_aggregate, logs:, player_message:, registry_entry:)
      @log_aggregate  = log_aggregate
      @logs           = logs
      @player_message = player_message
      @registry_entry = registry_entry
    end

    def as_hash
      {
        registry_entry_uuid: @log_aggregate.registry_entry_uuid,
        adventure_id:        @log_aggregate.adventure_id,
        first_at:            @log_aggregate.first_at,
        last_at:             @log_aggregate.last_at,
        step_count:          @log_aggregate.step_count,
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
