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
    @runtime = DungeonMaster::EntryRuntime.new(adventure: adventure, user: user)
    @prompt_execution = DungeonMaster::EntryServices::PromptExecution.new(runtime: @runtime)
    @resume_execution = DungeonMaster::EntryServices::PipelineResumeExecution.new(runtime: @runtime)
  end

  # ----------------------------------------------------------------
  # Phase 1 — controller: persist player message + enqueue job
  # ----------------------------------------------------------------

  def prepare_prompt(player_input)
    runtime.messenger.persist_message(role: "player", content: player_input, message_type: "narrative")
  end

  def prepare_initiative(player_initiative)
    runtime.messenger.persist_message(
      role: "player",
      content: "Initiative: #{player_initiative}",
      message_type: "initiative_result",
      metadata: { initiative: player_initiative })
  end

  def prepare_roll(roll_results_from_player)
    runtime.messenger.persist_message(
      role: "player",
      content: DungeonMaster::Rolls::RollResultsText.format(roll_results_from_player),
      message_type: "roll_result",
      metadata: { rolls: roll_results_from_player })
  end

  # ----------------------------------------------------------------
  # Phase 2 — Sidekiq job: run pipeline + broadcast via ActionCable
  # ----------------------------------------------------------------

  def execute_prompt(player_input, player_message_id:, mode: nil)
    prompt_execution.call(player_input: player_input, player_message_id: player_message_id, prompt_mode: mode)
  end

  def execute_rolls(roll_results_text, player_message_id:)
    resume_execution.call(player_message_id: player_message_id) do
      metadata = DungeonMaster::Rolls::AdventureMechanicalState.latest_roll_metadata(runtime.adventure)
      submitted_rolls = runtime.adventure.adventure_messages.find(player_message_id).metadata&.dig("rolls")
      runtime.resume_or_start_pipeline!(metadata, roll_results_text)
      runtime.ensure_run_pipeline!
      DungeonMaster::PipelineTiming.run(runtime.log) do
        runtime.pipeline_engine.run_rolls(roll_results_text, metadata, submitted_rolls: submitted_rolls)
      end
    end
  end

  def execute_initiative(player_initiative, player_message_id:)
    resume_execution.call(player_message_id: player_message_id) do
      metadata = DungeonMaster::Rolls::AdventureMechanicalState.latest_initiative_metadata(runtime.adventure)
      resume_content = "Initiative: #{player_initiative}"
      runtime.resume_or_start_pipeline!(metadata, resume_content)
      runtime.ensure_run_pipeline!
      DungeonMaster::PipelineTiming.run(runtime.log) do
        runtime.pipeline_engine.run_initiative(player_initiative.to_i, metadata)
      end
    end
  end

  # Serialize a message for JSON broadcast / API response.
  def self.message_json(message, admin: false)
    DungeonMaster::AdventurePlay::MessageSerializer.as_json(message, admin: admin)
  end

  private

  attr_reader :runtime, :prompt_execution, :resume_execution

  # Backward-compatible private seam used by usage-limit specs.
  def enforce_pipeline_policy!
    runtime.enforce_pipeline_policy!
  end
end
