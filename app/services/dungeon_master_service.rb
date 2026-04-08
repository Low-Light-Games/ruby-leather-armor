# frozen_string_literal: true

# Thin orchestrator for the AI Dungeon Master.
#
# Coordinates the pipeline, moderation gate, logging, and collaborators:
#   - AdventurePolicy#pipeline? — billing gate (also enforced on POST …/messages* in the controller)
#   - DungeonMaster::AdventurePlay::PipelineMessenger — persist messages, map results,
#     progressive narration broadcasts
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
    @messenger = DungeonMaster::AdventurePlay::PipelineMessenger.new(
      adventure: adventure, log: @log, user: user)
  end

  # ----------------------------------------------------------------
  # Phase 1 — controller: persist player message + enqueue job
  # ----------------------------------------------------------------

  def prepare_prompt(player_input)
    @messenger.persist_message(role: "player", content: player_input, message_type: "narrative")
  end

  def prepare_initiative(player_initiative)
    @messenger.persist_message(
      role: "player",
      content: "Initiative: #{player_initiative}",
      message_type: "initiative_result",
      metadata: { initiative: player_initiative })
  end

  def prepare_roll(roll_results_from_player)
    @messenger.persist_message(
      role: "player",
      content: DungeonMaster::Rolls::RollResultsText.format(roll_results_from_player),
      message_type: "roll_result",
      metadata: { rolls: roll_results_from_player })
  end

  # ----------------------------------------------------------------
  # Phase 2 — Sidekiq job: run pipeline + broadcast via ActionCable
  # ----------------------------------------------------------------

  def execute_prompt(player_input, player_message_id:, mode: nil)
    enforce_pipeline_policy!
    @log.log_abandoned_pipeline_if_needed!
    DungeonMaster::Rolls::AdventureMechanicalState.auto_finalize_pending_initiative!(
      adventure: @adventure, sheet: @sheet, log: @log)

    if @user&.trusted?
      ModerationCheckJob.perform_later(@user.id, player_input)
    else
      mod = DungeonMaster::ModerationService.call(player_input, user: @user)
      if mod.flagged?
        return [@messenger.persist_message(role: "dm", content: mod.response_text,
                                            message_type: "moderation_flagged")]
      end
    end

    @log.player_message_id = player_message_id
    @log.start_pipeline_run!(player_input)

    result = DungeonMaster::PipelineTiming.run(@log) { pipeline.run_prompt(player_input, mode: mode) }
    @messenger.messages_for(result)
  rescue UsageLimitExceeded => e
    @messenger.usage_limit_rejection_messages(e)
  rescue SanitizationRejected => e
    @messenger.sanitization_failure_messages(e)
  rescue AiError, StandardError => e
    @messenger.pipeline_exception_messages(e)
  end

  def execute_rolls(roll_results_text, player_message_id:)
    execute_player_resume(player_message_id) do
      metadata = DungeonMaster::Rolls::AdventureMechanicalState.latest_roll_metadata(@adventure)
      resume_or_start_pipeline!(metadata, roll_results_text)
      DungeonMaster::PipelineTiming.run(@log) { pipeline.run_rolls(roll_results_text, metadata) }
    end
  end

  def execute_initiative(player_initiative, player_message_id:)
    execute_player_resume(player_message_id) do
      metadata = DungeonMaster::Rolls::AdventureMechanicalState.latest_initiative_metadata(@adventure)
      resume_content = "Initiative: #{player_initiative}"
      resume_or_start_pipeline!(metadata, resume_content)
      DungeonMaster::PipelineTiming.run(@log) { pipeline.run_initiative(player_initiative.to_i, metadata) }
    end
  end

  # Serialize a message for JSON broadcast / API response.
  def self.message_json(message, admin: false)
    DungeonMaster::AdventurePlay::MessageSerializer.as_json(message, admin: admin)
  end

  private

  def enforce_pipeline_policy!
    raise UsageLimitExceeded unless AdventurePolicy.new(@user, @adventure).pipeline?
  end

  def pipeline
    @pipeline ||= DungeonMaster::Pipeline.new(
      adventure: @adventure, config: @config, ai: @ai, log: @log, sheet: @sheet,
      on_progress: method(:broadcast_pipeline_progress),
      on_sheet_update: method(:broadcast_sheet_update),
      on_narrative: @messenger.method(:handle_progressive_narrative))
  end

  def broadcast_pipeline_progress(message)
    AdventureChannel.broadcast_to(@adventure, { type: "pipeline_progress", message: message })
  end

  def broadcast_sheet_update
    AdventureChannel.broadcast_to(@adventure, { type: "sheet_update" })
  end

  def execute_player_resume(player_message_id)
    enforce_pipeline_policy!
    @log.player_message_id = player_message_id
    result = yield
    @messenger.messages_for(result)
  rescue UsageLimitExceeded => e
    @messenger.usage_limit_rejection_messages(e)
  rescue AiError, StandardError => e
    @messenger.pipeline_exception_messages(e)
  end

  def resume_or_start_pipeline!(metadata, message_content)
    original_run_id = metadata&.dig("pipeline_run_id")
    if original_run_id.present?
      @log.resume_pipeline_run!(original_run_id, message_content)
    else
      @log.start_pipeline_run!(message_content)
    end
  end
end
