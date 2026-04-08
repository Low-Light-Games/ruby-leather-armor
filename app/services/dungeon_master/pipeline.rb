# frozen_string_literal: true

module DungeonMaster
  # Pure pipeline logic for the AI Dungeon Master.
  #
  # Runs steps in order and returns a result hash describing what happened.
  # Does NOT persist messages or handle errors -- the calling service
  # (DungeonMasterService) is responsible for those side effects.
  #
  # Flow:
  #   run_prompt          -> Concerns::EntryPoints + phases (see pipeline/phases/*):
  #                           IntakeDangerGate -> DmQueryBranch -> OrchestrateCompoundActions
  #                         OrchestrateCompoundActions: run_sequencer -> ActionQueueRunner
  #                           -> per loop row: AdventureLoopResolution#resolve -> narrate (Concerns::NarrationCoordination)
  #                         Per-step narrative when action_queue is progressive / progressive_continuity
  #   run_rolls           -> AdventureLoopResolution#finish_resolution -> continue queue if remaining -> narrative phase
  #
  # Orchestration is split across Pipeline::Concerns — see pipeline/concerns/*.rb.
  #
  class Pipeline
    # Step mixins add private methods to this instance. They do not run in list order here.
    #
    # **Outer turn** (visible in `#run_prompt` + pipeline/action_queue_runner.rb):
    #   Intake, DmQuery, Sequencer — then each queued line calls `resolve` (AdventureLoopResolution).
    #
    # **Inner resolution** (one AdventureLoop row — see adventure_loop_resolution.rb `#resolve`):
    #   ParallelEvaluation runs beacon + *AI* mechanical_evaluation (Node /sequential) +
    #   roll_qualifier; then, when `needs_mechanics`, SanityChecker →
    #   MechanicalEvaluation (`merge_mechanical_evaluations` + `merge_mechanical_evaluations_and_prepare_rolls`) →
    #   Mechanic / TimeKeeper / … as the path continues.
    #
    # The named AI step `mechanical_evaluation` is invoked from Steps::ParallelEvaluation.
    include Steps::Helpers
    include Steps::EvaluatorTransport
    include Steps::Intake
    include Steps::DmQuery
    include Steps::Sequencer
    include Steps::MechanicalEvaluation
    include Steps::SanityChecker
    include Steps::ParallelEvaluation
    include Steps::Mechanic
    include Steps::Momentum
    include Steps::TimeKeeper
    include Steps::Stagehand
    include Steps::Chronicler
    include Steps::Narrate
    include Steps::ContextUpdate
    include AdventureLoopResolution
    include Mutations

    include Concerns::NarrationCoordination
    include Concerns::ContextCoordination
    include Concerns::EntryPoints

    attr_reader :adventure, :config, :log, :ai, :sheet, :loop

    def initialize(adventure:, config:, ai:, log:, sheet:, on_progress: nil, on_sheet_update: nil, on_narrative: nil)
      @adventure        = adventure
      @config           = config
      @ai               = ai
      @log              = log
      @sheet            = sheet
      @loop             = nil
      @on_progress      = on_progress
      @on_sheet_update  = on_sheet_update
      @on_narrative     = on_narrative
    end

    private

    # Reload intent + mechanical merge state from the roll_request message saved at :awaiting_rolls.
    def restore_roll_pause_inputs(metadata)
      Rolls::RollRequestMetadata.resume_inputs(metadata)
    end

    def story_has_plot_data?
      StoryNpc.where(story_id: @adventure.story_id).exists? ||
        StoryClue.where(story_id: @adventure.story_id).exists?
    end

    def resolve_plot(intent, verdict_outcome: nil, encounter_triggered: false)
      return unless story_has_plot_data?

      run_chronicler(intent, verdict_outcome: verdict_outcome, encounter_triggered: encounter_triggered)
    end

    # ----------------------------------------------------------------
    # AdventureLoop lifecycle helpers
    # ----------------------------------------------------------------

    def create_adventure_loop(action_text, sequence_index)
      AdventureLoop.create!(
        adventure: @adventure,
        pipeline_run_id: @log.pipeline_run_id,
        sequence_index: sequence_index,
        raw_action: action_text&.truncate(500),
        player_intent: action_text&.truncate(500),
        status: "pending"
      )
    end

    def restore_paused_loop!
      return unless @log.pipeline_run_id
      @loop = AdventureLoop.for_pipeline(@log.pipeline_run_id).paused.order(:created_at).last
    end

    def tl(step, summary)
      { "step" => step.to_s, "summary" => summary.to_s.truncate(200), "at" => Time.current.iso8601 }
    end
  end
end
