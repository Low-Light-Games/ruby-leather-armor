# frozen_string_literal: true

module DungeonMaster
  # Pure pipeline logic for the AI Dungeon Master.
  #
  # Runs steps in order and returns a result hash describing what happened.
  # Does NOT persist messages or handle errors -- the calling service
  # (DungeonMasterService) is responsible for those side effects.
  #
  # Flow:
  #   run_prompt          -> Concerns::EntryPoints + phases (see pipeline_engine/phases/*):
  #                           IntakeDangerGate -> DmQueryBranch -> OrchestrateCompoundActions
  #                         OrchestrateCompoundActions: run_sequencer -> ActionQueueRunner
  #                           -> per loop row: AdventureLoopResolution#resolve -> narrate (Concerns::NarrationCoordination)
  #                         Per-step narrative when action_queue is progressive / progressive_continuity
  #   run_rolls           -> AdventureLoopResolution#finish_resolution -> continue queue if remaining -> narrative phase
  #
  # Orchestration is split across PipelineEngine::Concerns — see pipeline_engine/concerns/*.rb.
  #
  class PipelineEngine
    # Step mixins add private methods; order here is not execution order. Outer turn: phases →
    # ActionQueueRunner → `AdventureLoopResolution#resolve` per queued line. Inner path: ParallelEvaluation
    # → (optional) SanityChecker + MechanicalEvaluation roll prep → Combat GM or Mechanic / TimeKeeper / …
    include Steps::Helpers
    include Steps::EvaluatorTransport
    include Steps::Intake
    include Steps::DmQuery
    include Steps::Sequencer
    include Steps::MechanicalEvaluation
    include Steps::SanityChecker
    include Steps::ParallelEvaluation
    include Steps::RollRequest
    include Steps::Mechanic
    include Steps::CombatGm
    include Steps::Momentum
    include Steps::TimeKeeper
    include Steps::Stagehand
    include Steps::Chronicler
    include Steps::Narrate
    include Steps::ContextUpdate
    include AdventureLoopResolution
    include Mutations
    include Steps::WorldTurn

    include Concerns::NarrationCoordination
    include Concerns::ContextCoordination
    include Concerns::EntryPoints

    attr_reader :adventure, :config, :log, :ai, :sheet, :loop, :run_pipeline

    def initialize(adventure:, config:, ai:, log:, sheet:, run_pipeline: nil,
      on_progress: nil, on_sheet_update: nil, on_narrative: nil)
      @adventure        = adventure
      @config           = config
      @ai               = ai
      @log              = log
      @sheet            = sheet
      @loop             = nil
      @run_pipeline     = run_pipeline
      @on_progress      = on_progress
      @on_sheet_update  = on_sheet_update
      @on_narrative     = on_narrative
    end

    def attach_run_pipeline!(record)
      @run_pipeline = record
    end

    def bind_current_loop!(adventure_loop)
      @loop = adventure_loop
      @log.adventure_loop = adventure_loop
    end

    def clear_current_loop!
      @loop = nil
      @log.adventure_loop = nil
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

      # v1 latency: skip Chronicler while combat is active (revisit if combat rounds gain plot beats).
      return if combat_active?

      run_chronicler(intent, verdict_outcome: verdict_outcome, encounter_triggered: encounter_triggered)
    end

    # ----------------------------------------------------------------
    # AdventureLoop lifecycle helpers
    # ----------------------------------------------------------------

    def create_adventure_loop(action_text, sequence_index)
      attrs = adventure_loop_attributes(action_text, sequence_index)
      attrs[:pipeline] = @run_pipeline if @run_pipeline
      AdventureLoop.create!(attrs)
    end

    def restore_paused_loop!
      return unless @log.registry_entry_uuid

      bind_current_loop!(
        AdventureLoop.for_registry_entry(@log.registry_entry_uuid).paused.order(:created_at).last
      )
    end

    def tl(step, summary)
      { "step" => step.to_s, "summary" => summary.to_s.truncate(200), "at" => Time.current.iso8601 }
    end

    def adventure_loop_attributes(action_text, sequence_index)
      {
        adventure:           @adventure,
        registry_entry_uuid: @log.registry_entry_uuid,
        sequence_index:      sequence_index,
        raw_action:          action_text&.truncate(500),
        player_intent:       action_text&.truncate(500),
        status:              "pending"
      }
    end
  end
end
