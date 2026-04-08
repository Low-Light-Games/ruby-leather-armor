# frozen_string_literal: true

# Thin orchestrator for the AI Dungeon Master.
#
# Delegates pipeline logic to DungeonMaster::Pipeline and handles the
# two side-effect concerns that don't belong in the pipeline itself:
#   1. Persisting AdventureMessage records
#   2. Catching errors and producing player-safe messages
#
# All pipeline actions are async: the controller calls prepare_* (persists the
# player message and returns immediately with 202), then enqueues a Sidekiq job
# that calls execute_* (runs the pipeline and broadcasts results via ActionCable).
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
  # Phase 1 — controller: persist player message + enqueue job
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
  # Phase 2 — Sidekiq job: run pipeline + broadcast via ActionCable
  # ----------------------------------------------------------------

  def execute_prompt(player_input, player_message_id:, mode: nil)
    enforce_usage_limit!
    @log.log_abandoned_pipeline_if_needed!
    auto_finalize_pending_initiative!

    if @user&.trusted?
      ModerationCheckJob.perform_later(@user.id, player_input)
    else
      mod = DungeonMaster::ModerationService.call(player_input, user: @user)
      if mod.flagged?
        return [persist_message(role: "dm", content: mod.response_text,
                                message_type: "moderation_flagged")]
      end
    end

    @log.player_message_id = player_message_id
    @log.start_pipeline_run!(player_input)

    result = run_timed_pipeline { pipeline.run_prompt(player_input, mode: mode) }
    messages_for(result)
  rescue UsageLimitExceeded => e
    execute_rescue_usage_limit(e)
  rescue SanitizationRejected => e
    @log.error_pipeline_run!
    [persist_message(role: "system", content: e.message, message_type: "sanitization_fail")]
  rescue AiError, StandardError => e
    execute_rescue_pipeline_error(e)
  end

  def execute_rolls(roll_results_text, player_message_id:)
    execute_player_resume(player_message_id) do
      metadata = latest_roll_metadata
      resume_or_start_pipeline!(metadata, roll_results_text)
      run_timed_pipeline { pipeline.run_rolls(roll_results_text, metadata) }
    end
  end

  def execute_initiative(player_initiative, player_message_id:)
    execute_player_resume(player_message_id) do
      metadata = latest_initiative_metadata
      resume_content = "Initiative: #{player_initiative}"
      resume_or_start_pipeline!(metadata, resume_content)
      run_timed_pipeline { pipeline.run_initiative(player_initiative.to_i, metadata) }
    end
  end

  # Serialize a message for JSON broadcast / API response.
  def self.message_json(message, admin: false)
    DungeonMaster::AdventurePlay::MessageSerializer.as_json(message, admin: admin)
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
    @pipeline ||= DungeonMaster::Pipeline.new(
      adventure: @adventure, config: @config, ai: @ai, log: @log, sheet: @sheet,
      on_progress: method(:broadcast_pipeline_progress),
      on_sheet_update: method(:broadcast_sheet_update),
      on_narrative: method(:handle_progressive_narrative))
  end

  def broadcast_pipeline_progress(message)
    AdventureChannel.broadcast_to(@adventure, { type: "pipeline_progress", message: message })
  end

  def broadcast_sheet_update
    AdventureChannel.broadcast_to(@adventure, { type: "sheet_update" })
  end

  # Called by the pipeline for each resolved action when per_action_narration is on.
  # Persists and broadcasts the narrative immediately so the player sees it in real time,
  # without waiting for the full pipeline to finish.
  def handle_progressive_narrative(narrative_entry)
    msg = persist_message(
      role: "dm",
      content: narrative_entry[:narrative],
      message_type: "narrative",
      metadata: DungeonMaster::AdventurePlay::ProgressiveNarrativeMetadata.for_entry(narrative_entry)
    )

    admin = @user&.admin?
    to_broadcast = [DungeonMaster::AdventurePlay::MessageSerializer.as_json(msg, admin: admin)]

    if narrative_entry[:adventure_complete]
      complete_msg = persist_message(
        role: "system",
        content: "The adventure has reached its conclusion.",
        message_type: "adventure_complete")
      to_broadcast << DungeonMaster::AdventurePlay::MessageSerializer.as_json(complete_msg, admin: admin)
    end

    AdventureChannel.broadcast_to(@adventure, { type: "pipeline_action_result", messages: to_broadcast })
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
      meta = DungeonMaster::Rolls::RollRequestMetadata.build_persist_metadata(
        merged: result[:merged],
        intent: result[:intent],
        adventure: @adventure,
        remaining_actions: result[:remaining_actions]
      )
      [persist_message(
        role: "dm",
        content: DungeonMaster::Rolls::RollExplanation.from_summaries(result[:merged][:mechanical_summaries]),
        message_type: "roll_request",
        metadata: meta)]

    when :awaiting_initiative
      meta = DungeonMaster::AdventurePlay::InitiativeRequestMetadata.for_awaiting_initiative(result)
      encounter_intro = AdventureLoop.for_pipeline(@log.pipeline_run_id)
                                      .paused.order(:created_at).last
                                      &.get("pipeline_outcome")
      initiative_content = [encounter_intro.presence, "Roll for initiative!"].compact.join("\n\n")
      [persist_message(
        role: "dm",
        content: initiative_content,
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

    when :narrated_sequence
      signal_done_to_the_frontend
    end
  end

  # ----------------------------------------------------------------
  # Helpers
  # ----------------------------------------------------------------

  # Progressive narration already emitted each chunk; an empty `pipeline_result` tells
  # the client to clear the thinking state.
  def signal_done_to_the_frontend
    []
  end

  def execute_player_resume(player_message_id)
    enforce_usage_limit!
    @log.player_message_id = player_message_id
    result = yield
    messages_for(result)
  rescue UsageLimitExceeded => e
    execute_rescue_usage_limit(e)
  rescue AiError, StandardError => e
    execute_rescue_pipeline_error(e)
  end

  def execute_rescue_usage_limit(error)
    [persist_message(role: "system", content: error.message, message_type: "usage_limit")]
  end

  def execute_rescue_pipeline_error(error)
    @log.capture_pipeline_exception!(error)
    @log.error_pipeline_run!
    [persist_message(
      role: "system",
      content: "The Dungeon Master is momentarily distracted... (#{player_facing_error(error)})",
      message_type: "narrative")]
  end

  def resume_or_start_pipeline!(metadata, message_content)
    original_run_id = metadata&.dig("pipeline_run_id")
    if original_run_id.present?
      @log.resume_pipeline_run!(original_run_id, message_content)
    else
      @log.start_pipeline_run!(message_content)
    end
  end

  def latest_roll_metadata
    @adventure.adventure_messages.for_message_types(["roll_request"]).newest_first.first&.metadata || {}
  end

  def latest_initiative_metadata
    @adventure.adventure_messages.for_message_types(["initiative_request"]).newest_first.first&.metadata || {}
  end

  def auto_finalize_pending_initiative!
    msgs = @adventure.adventure_messages
    last_init_msg = msgs.for_message_types(["initiative_request"]).newest_first.first
    return unless last_init_msg&.metadata&.dig("creature_data")

    last_player_response = msgs.from_players
                               .where("created_at > ?", last_init_msg.created_at)
                               .newest_first.first
    return unless last_player_response
    return if last_player_response.message_type == "initiative_result"

    player_init = DungeonMaster::Utilities::Warmaster.auto_roll_player_initiative(@sheet)
    creature_data = last_init_msg.metadata["creature_data"].map(&:deep_symbolize_keys)

    combat_data = DungeonMaster::Utilities::Warmaster.compute_combat_initialization(
      creature_data: creature_data, player_initiative: player_init)
    @adventure.update!(combat_context: combat_data)

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
