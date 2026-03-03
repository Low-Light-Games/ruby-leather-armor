# frozen_string_literal: true

# Thin orchestrator for the AI Dungeon Master.
#
# Delegates pipeline logic to DungeonMaster::Pipeline and handles the
# two side-effect concerns that don't belong in the pipeline itself:
#   1. Persisting AdventureMessage records
#   2. Catching errors and producing player-safe messages
#
# See DungeonMaster::Pipeline for the step-by-step flow.
#
class DungeonMasterService
  SanitizationRejected     = DungeonMaster::SanitizationRejected
  AiError                  = DungeonMaster::AiError
  TokenBudgetExceededError = DungeonMaster::TokenBudgetExceededError

  def initialize(adventure, user:)
    @adventure = adventure
    @user      = user
    @config    = DmConfig.instance
    @ai        = DungeonMaster::AiClient.new(@config)
    @log       = DungeonMaster::Logging.new(adventure: adventure, user: user)
    @sheet     = DungeonMaster::CharacterBlock.load_sheet(adventure)
  end

  # ----------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------

  def process_player_prompt(player_input, mode: nil)
    player_msg = persist_message(role: "player", content: player_input, message_type: "narrative")
    @log.player_message_id = player_msg.id
    @log.start_pipeline_run!(player_input)

    result = pipeline.run_prompt(player_input, mode: mode)
    { messages: [player_msg] + messages_for(result) }
  rescue SanitizationRejected => e
    rejection = persist_message(role: "system", content: e.message, message_type: "sanitization_fail")
    { messages: [player_msg, rejection] }
  rescue AiError => e
    error_msg = persist_message(
      role: "system",
      content: "The Dungeon Master is momentarily distracted... (#{player_facing_error(e)})",
      message_type: "narrative")
    { messages: [player_msg, error_msg] }
  end

  def process_roll_result(roll_results_from_player)
    metadata = latest_roll_metadata
    roll_msg = persist_message(
      role: "player",
      content: format_roll_results(roll_results_from_player),
      message_type: "roll_result",
      metadata: { rolls: roll_results_from_player })
    @log.player_message_id = roll_msg.id
    @log.start_pipeline_run!(format_roll_results(roll_results_from_player))

    result = pipeline.run_rolls(format_roll_results(roll_results_from_player), metadata)
    { messages: [roll_msg] + messages_for(result) }
  rescue AiError => e
    error_msg = persist_message(
      role: "system",
      content: "The Dungeon Master is momentarily distracted... (#{player_facing_error(e)})",
      message_type: "narrative")
    { messages: [roll_msg, error_msg] }
  end

  private

  # ----------------------------------------------------------------
  # Pipeline
  # ----------------------------------------------------------------

  def pipeline
    @pipeline ||= DungeonMaster::Pipeline.new(
      adventure: @adventure, config: @config, ai: @ai, log: @log, sheet: @sheet)
  end

  # ----------------------------------------------------------------
  # Result -> Messages mapping
  # ----------------------------------------------------------------

  def messages_for(result)
    case result[:action]
    when :rejected
      [persist_message(
        role: "system",
        content: result[:reason] || "Your input was rejected. Please try a valid in-character action.",
        message_type: "sanitization_fail")]

    when :dm_query
      [persist_message(role: "dm", content: result[:answer], message_type: "dm_query")]

    when :awaiting_rolls
      meta = {
        roll_requests: result[:merged][:player_rolls],
        pending_npc_actions: result[:merged][:npc_actions],
        pending_consequences: result[:merged][:consequences],
        ruling_summaries: result[:merged][:ruling_summaries],
        intent: result[:intent]
      }
      meta[:time_span_parameters] = result[:merged][:time_span_parameters] if result[:time_spanning]
      [persist_message(
        role: "dm",
        content: roll_explanation(result[:merged][:ruling_summaries]),
        message_type: "roll_request",
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

  def latest_roll_metadata
    last_roll_msg = @adventure.adventure_messages
                              .where(message_type: "roll_request")
                              .order(created_at: :desc).first
    last_roll_msg&.metadata || {}
  end

  def player_facing_error(error)
    case error
    when TokenBudgetExceededError
      "Could not reach the AI service. Please try again shortly."
    else
      error.message
    end
  end

  def roll_explanation(ruling_summaries)
    return "The DM awaits your rolls..." if ruling_summaries.blank?

    ruling_summaries
      .map { |s| s.sub(/\A\[\w+\]\s*/, "") }
      .join(" ")
      .presence || "The DM awaits your rolls..."
  end

  def persist_message(role:, content:, message_type:, metadata: {})
    if role == "dm" && @log.pipeline_run_id
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
      "Rolled #{r[:roll_value]} for: #{r[:roll_description]}"
    end.join("\n")
  end
end
