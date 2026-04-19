# frozen_string_literal: true

# Thin orchestrator for the AI Dungeon Master.
#
# Coordinates the pipeline, moderation gate, logging, and collaborators:
#   - AdventurePolicy#pipeline? — billing gate (also enforced on POST …/messages* in the controller)
#   - DungeonMaster::AdventurePlay::PipelineMessenger — persist messages, map results,
#     progressive narration broadcasts
#
# See DungeonMaster::PipelineEngine for the step-by-step flow.
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
    # A fresh prompt supersedes any pending roll request; only explicit roll submissions
    # should resume the paused mechanical branch.
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
    @log.start_registry_entry!(player_input)
    ensure_run_pipeline!

    result = DungeonMaster::PipelineTiming.run(@log) { pipeline_engine.run_prompt(player_input, mode: mode) }
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
      submitted_rolls = @adventure.adventure_messages.find(player_message_id).metadata&.dig("rolls")
      resume_or_start_pipeline!(metadata, roll_results_text)
      ensure_run_pipeline!
      DungeonMaster::PipelineTiming.run(@log) { pipeline_engine.run_rolls(roll_results_text, metadata, submitted_rolls: submitted_rolls) }
    end
  end

  def execute_initiative(player_initiative, player_message_id:)
    execute_player_resume(player_message_id) do
      metadata = DungeonMaster::Rolls::AdventureMechanicalState.latest_initiative_metadata(@adventure)
      resume_content = "Initiative: #{player_initiative}"
      resume_or_start_pipeline!(metadata, resume_content)
      ensure_run_pipeline!
      DungeonMaster::PipelineTiming.run(@log) { pipeline_engine.run_initiative(player_initiative.to_i, metadata) }
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

  def pipeline_engine
    @pipeline_engine ||= DungeonMaster::PipelineEngine.new(
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
    original_uuid = metadata&.dig("registry_entry_uuid")
    if original_uuid.present?
      @log.resume_registry_entry!(original_uuid, message_content)
    else
      @log.start_registry_entry!(message_content)
    end
  end

  # Domain Pipeline AR (through-line for loops) — separate from PipelineRegistryEntry.
  def ensure_run_pipeline!
    uuid = @log.registry_entry_uuid
    return if uuid.blank?

    existing_id = AdventureLoop.where(registry_entry_uuid: uuid).where.not(pipeline_id: nil).limit(1).pick(:pipeline_id)
    pl = if existing_id
           Pipeline.find_by(id: existing_id)
         else
           Pipeline.create!(adventure: @adventure, player_message_id: @log.player_message_id)
         end
    pipeline_engine.attach_run_pipeline!(pl) if pl
  end
end
