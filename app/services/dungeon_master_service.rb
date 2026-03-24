# frozen_string_literal: true

# Thin orchestrator for the AI Dungeon Master.
#
# Delegates pipeline logic to DungeonMaster::Pipeline and handles the
# two side-effect concerns that don't belong in the pipeline itself:
#   1. Persisting AdventureMessage records
#   2. Catching errors and producing player-safe messages
#
# Supports two modes of operation:
#   Sync  — process_player_prompt / process_roll_result (original, blocking)
#   Async — prepare_prompt + execute_prompt (split across controller + Sidekiq job)
#
# See DungeonMaster::Pipeline for the step-by-step flow.
#
class DungeonMasterService
  SanitizationRejected     = DungeonMaster::SanitizationRejected
  AiError                  = DungeonMaster::AiError
  TokenBudgetExceededError = DungeonMaster::TokenBudgetExceededError
  UsageLimitExceeded       = DungeonMaster::UsageLimitExceeded

  def initialize(adventure, user:)
    @adventure = adventure
    @user      = user
    @config    = DmConfig.instance
    @ai        = DungeonMaster::AiClient.new(@config)
    @log       = DungeonMaster::Logging.new(adventure: adventure, user: user)
    @sheet     = DungeonMaster::CharacterBlock.load_sheet(adventure)
  end

  # ----------------------------------------------------------------
  # Sync API (original — blocks until pipeline completes)
  # ----------------------------------------------------------------

  def process_player_prompt(player_input, mode: nil)
    enforce_usage_limit!
    maybe_log_abandoned_pipeline
    auto_finalize_pending_initiative!

    player_msg = persist_message(role: "player", content: player_input, message_type: "narrative")
    @log.player_message_id = player_msg.id
    @log.start_pipeline_run!(player_input)

    result = run_timed_pipeline { pipeline.run_prompt(player_input, mode: mode) }
    { messages: [player_msg] + messages_for(result) }
  rescue UsageLimitExceeded => e
    player_msg ||= persist_message(role: "player", content: player_input, message_type: "narrative")
    limit_msg = persist_message(role: "system", content: e.message, message_type: "usage_limit")
    { messages: [player_msg, limit_msg] }
  rescue SanitizationRejected => e
    @log.error_pipeline_run!
    rejection = persist_message(role: "system", content: e.message, message_type: "sanitization_fail")
    { messages: [player_msg, rejection] }
  rescue AiError, StandardError => e
    capture_pipeline_error(e)
    @log.error_pipeline_run!
    error_msg = persist_message(
      role: "system",
      content: "The Dungeon Master is momentarily distracted... (#{player_facing_error(e)})",
      message_type: "narrative")
    { messages: [player_msg, error_msg] }
  end

  def process_roll_result(roll_results_from_player)
    enforce_usage_limit!

    metadata = latest_roll_metadata
    roll_msg = persist_message(
      role: "player",
      content: format_roll_results(roll_results_from_player),
      message_type: "roll_result",
      metadata: { rolls: roll_results_from_player })
    @log.player_message_id = roll_msg.id
    resume_or_start_pipeline!(metadata, format_roll_results(roll_results_from_player))

    result = run_timed_pipeline { pipeline.run_rolls(format_roll_results(roll_results_from_player), metadata) }
    { messages: [roll_msg] + messages_for(result) }
  rescue UsageLimitExceeded => e
    limit_msg = persist_message(role: "system", content: e.message, message_type: "usage_limit")
    { messages: [limit_msg] }
  rescue AiError, StandardError => e
    capture_pipeline_error(e)
    @log.error_pipeline_run!
    error_msg = persist_message(
      role: "system",
      content: "The Dungeon Master is momentarily distracted... (#{player_facing_error(e)})",
      message_type: "narrative")
    { messages: [roll_msg, error_msg] }
  end

  def process_initiative_result(player_initiative)
    enforce_usage_limit!

    metadata = latest_initiative_metadata
    init_msg = persist_message(
      role: "player",
      content: "Initiative: #{player_initiative}",
      message_type: "initiative_result",
      metadata: { initiative: player_initiative })
    @log.player_message_id = init_msg.id
    resume_or_start_pipeline!(metadata, "Initiative: #{player_initiative}")

    result = run_timed_pipeline { pipeline.run_initiative(player_initiative.to_i, metadata) }
    { messages: [init_msg] + messages_for(result) }
  rescue UsageLimitExceeded => e
    limit_msg = persist_message(role: "system", content: e.message, message_type: "usage_limit")
    { messages: [limit_msg] }
  rescue AiError, StandardError => e
    capture_pipeline_error(e)
    @log.error_pipeline_run!
    error_msg = persist_message(
      role: "system",
      content: "The Dungeon Master is momentarily distracted... (#{player_facing_error(e)})",
      message_type: "narrative")
    { messages: [init_msg, error_msg] }
  end

  # ----------------------------------------------------------------
  # Async API — Phase 1 (controller: persist + enqueue)
  # ----------------------------------------------------------------

  def prepare_prompt(player_input)
    persist_message(role: "player", content: player_input, message_type: "narrative")
  end

  def prepare_initiative(player_initiative)
    persist_message(
      role: "player",
      content: "Initiative: #{player_initiative}",
      message_type: "initiative_result",
      metadata: { initiative: player_initiative })
  end

  def prepare_roll(roll_results_from_player)
    roll_msg = persist_message(
      role: "player",
      content: format_roll_results(roll_results_from_player),
      message_type: "roll_result",
      metadata: { rolls: roll_results_from_player })
    roll_msg
  end

  # ----------------------------------------------------------------
  # Async API — Phase 2 (Sidekiq job: run pipeline + broadcast)
  # ----------------------------------------------------------------

  def execute_prompt(player_input, player_message_id:, mode: nil)
    enforce_usage_limit!
    maybe_log_abandoned_pipeline
    auto_finalize_pending_initiative!

    @log.player_message_id = player_message_id
    @log.start_pipeline_run!(player_input)

    result = run_timed_pipeline { pipeline.run_prompt(player_input, mode: mode) }
    messages_for(result)
  rescue UsageLimitExceeded => e
    [persist_message(role: "system", content: e.message, message_type: "usage_limit")]
  rescue SanitizationRejected => e
    @log.error_pipeline_run!
    [persist_message(role: "system", content: e.message, message_type: "sanitization_fail")]
  rescue AiError, StandardError => e
    capture_pipeline_error(e)
    @log.error_pipeline_run!
    [persist_message(
      role: "system",
      content: "The Dungeon Master is momentarily distracted... (#{player_facing_error(e)})",
      message_type: "narrative")]
  end

  def execute_rolls(roll_results_text, player_message_id:)
    enforce_usage_limit!

    @log.player_message_id = player_message_id
    metadata = latest_roll_metadata
    resume_or_start_pipeline!(metadata, roll_results_text)

    result = run_timed_pipeline { pipeline.run_rolls(roll_results_text, metadata) }
    messages_for(result)
  rescue UsageLimitExceeded => e
    [persist_message(role: "system", content: e.message, message_type: "usage_limit")]
  rescue AiError, StandardError => e
    capture_pipeline_error(e)
    @log.error_pipeline_run!
    [persist_message(
      role: "system",
      content: "The Dungeon Master is momentarily distracted... (#{player_facing_error(e)})",
      message_type: "narrative")]
  end

  def execute_initiative(player_initiative, player_message_id:)
    enforce_usage_limit!

    @log.player_message_id = player_message_id
    metadata = latest_initiative_metadata
    resume_or_start_pipeline!(metadata, "Initiative: #{player_initiative}")

    result = run_timed_pipeline { pipeline.run_initiative(player_initiative.to_i, metadata) }
    messages_for(result)
  rescue UsageLimitExceeded => e
    [persist_message(role: "system", content: e.message, message_type: "usage_limit")]
  rescue AiError, StandardError => e
    capture_pipeline_error(e)
    @log.error_pipeline_run!
    [persist_message(
      role: "system",
      content: "The Dungeon Master is momentarily distracted... (#{player_facing_error(e)})",
      message_type: "narrative")]
  end

  # Serialize a message for JSON broadcast / API response.
  def self.message_json(message, admin: false)
    json = {
      id: message.id,
      role: message.role,
      content: message.content,
      message_type: message.message_type,
      metadata: message.metadata,
      created_at: message.created_at
    }
    if admin && message.role != "player"
      json[:pipeline_run_id] = message.metadata&.dig("pipeline_run_id")
    end
    json
  end

  private

  # ----------------------------------------------------------------
  # Pipeline timing
  # ----------------------------------------------------------------

  def run_timed_pipeline
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = yield
    segment_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
    @log.finish_pipeline_segment!(segment_ms)

    if result[:action].in?(%i[awaiting_rolls awaiting_initiative])
      @log.pause_pipeline_run!
    else
      @log.complete_pipeline_run!
    end

    result
  end

  # ----------------------------------------------------------------
  # Pipeline
  # ----------------------------------------------------------------

  def pipeline
    @pipeline ||= if @config.get("pipeline_mode") == "edge"
                    DungeonMaster::EdgePipeline.new(
                      adventure: @adventure, config: @config, ai: @ai, log: @log, sheet: @sheet)
                  else
                    DungeonMaster::Pipeline.new(
                      adventure: @adventure, config: @config, ai: @ai, log: @log, sheet: @sheet)
                  end
  end

  # ----------------------------------------------------------------
  # Result -> Messages mapping
  # ----------------------------------------------------------------

  def messages_for(result)
    case result[:action]
    when :rejected
      if result[:dm_message].present?
        [persist_message(role: "dm", content: result[:dm_message], message_type: "narrative")]
      else
        [persist_message(
          role: "system",
          content: result[:reason] || "Your input was rejected. Please try a valid in-character action.",
          message_type: "sanitization_fail")]
      end

    when :dm_query
      [persist_message(role: "dm", content: result[:answer], message_type: "dm_query")]

    when :awaiting_rolls
      meta = {
        roll_requests: result[:merged][:player_rolls],
        pending_npc_actions: result[:merged][:npc_actions],
        pending_consequences: result[:merged][:consequences],
        mechanical_summaries: result[:merged][:mechanical_summaries],
        intent: result[:intent],
        show_dc: @adventure.effective_dm_setting("show_roll_dc"),
        remaining_actions: result[:remaining_actions]
      }
      [persist_message(
        role: "dm",
        content: roll_explanation(result[:merged][:mechanical_summaries]),
        message_type: "roll_request",
        metadata: meta)]

    when :awaiting_initiative
      meta = {
        creature_data: result[:creature_data],
        intent: result[:intent],
        mutations: result[:mutations],
        remaining_actions: result[:remaining_actions]
      }
      [persist_message(
        role: "dm",
        content: "Roll for initiative!",
        message_type: "initiative_request",
        metadata: meta)]

    when :narrated
      msgs = [persist_message(role: "dm", content: result[:narrative], message_type: "narrative")]
      if result[:adventure_complete]
        msgs << persist_message(
          role: "system",
          content: "The adventure has reached its conclusion.",
          message_type: "adventure_complete")
      end
      msgs
    end
  end

  # ----------------------------------------------------------------
  # Helpers
  # ----------------------------------------------------------------

  def resume_or_start_pipeline!(metadata, message_content)
    original_run_id = metadata&.dig("pipeline_run_id")
    if original_run_id.present?
      @log.resume_pipeline_run!(original_run_id, message_content)
    else
      @log.start_pipeline_run!(message_content)
    end
  end

  def latest_roll_metadata
    last_roll_msg = @adventure.adventure_messages
                              .where(message_type: "roll_request")
                              .order(created_at: :desc).first
    last_roll_msg&.metadata || {}
  end

  def latest_initiative_metadata
    last_init_msg = @adventure.adventure_messages
                              .where(message_type: "initiative_request")
                              .order(created_at: :desc).first
    last_init_msg&.metadata || {}
  end

  def maybe_log_abandoned_pipeline
    last_request = @adventure.adventure_messages
                             .where(message_type: %w[roll_request initiative_request])
                             .order(created_at: :desc).first
    return unless last_request&.metadata&.dig("intent")

    last_player_msg = @adventure.adventure_messages
                                .where(role: "player")
                                .order(created_at: :desc).first
    return if last_player_msg&.message_type.in?(%w[roll_result initiative_result])

    intent_summary = last_request.metadata.dig("intent", "intention").to_s.truncate(80)
    @log.play_log!("pipeline_abandoned", "Previous pipeline abandoned (#{last_request.message_type}): player sent new input. " \
                   "Original intent: #{intent_summary}")
  end

  def auto_finalize_pending_initiative!
    last_init_msg = @adventure.adventure_messages
                              .where(message_type: "initiative_request")
                              .order(created_at: :desc).first
    return unless last_init_msg&.metadata&.dig("creature_data")

    last_player_response = @adventure.adventure_messages
                                     .where(role: "player")
                                     .where("created_at > ?", last_init_msg.created_at)
                                     .order(created_at: :desc).first
    return unless last_player_response
    return if last_player_response.message_type == "initiative_result"

    player_init = DungeonMaster::Utilities::Warmaster.auto_roll_player_initiative(@sheet)
    creature_data = last_init_msg.metadata["creature_data"].map(&:deep_symbolize_keys)

    DungeonMaster::Utilities::Warmaster.finalize_combat!(
      adventure: @adventure, creature_data: creature_data,
      player_initiative: player_init)

    @log.log!(:info, "Auto-rolled player initiative (#{player_init}) — player ignored initiative prompt")
  end

  def enforce_usage_limit!
    raise UsageLimitExceeded if @user&.usage_limit_reached?
  end

  def player_facing_error(error)
    case error
    when TokenBudgetExceededError
      "Could not reach the AI service. Please try again shortly."
    else
      error.message
    end
  end

  def capture_pipeline_error(error)
    Sentry.capture_exception(error) if defined?(Sentry)
  end

  def roll_explanation(ruling_summaries)
    return "The DM awaits your rolls..." if ruling_summaries.blank?

    ruling_summaries
      .map { |s| s.sub(/\A\[\w+\]\s*/, "") }
      .join(" ")
      .presence || "The DM awaits your rolls..."
  end

  def persist_message(role:, content:, message_type:, metadata: {})
    if role != "player" && @log.pipeline_run_id
      metadata = metadata.merge("pipeline_run_id" => @log.pipeline_run_id)
    end
    @adventure.adventure_messages.create!(
      role: role, content: content,
      message_type: message_type, metadata: metadata)
  end

  def format_roll_results(rolls)
    return rolls if rolls.is_a?(String)

    Array(rolls).map do |r|
      r = r.deep_symbolize_keys if r.respond_to?(:deep_symbolize_keys)
      case r[:resolution_method].to_s
      when "take_20"
        "Take 20 (result #{r[:roll_value]}) for: #{r[:roll_description]}"
      when "take_10"
        "Take 10 (result #{r[:roll_value]}) for: #{r[:roll_description]}"
      else
        "Rolled #{r[:roll_value]} for: #{r[:roll_description]}"
      end
    end.join("\n")
  end
end
