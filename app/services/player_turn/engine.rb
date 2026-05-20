# frozen_string_literal: true

module PlayerTurn
  class Engine
    include Steps::Helpers
    include Steps::EvaluatorTransport
    include Steps::Intake
    include Steps::GameMaster
    include Steps::Sequencer
    include Steps::SanityChecker
    include Steps::CastResolve
    include Steps::RollRequest
    include Steps::CombatRollRequest
    include Steps::Mechanic
    include Steps::CombatGm
    include Steps::TimeKeeper
    include Steps::Stagehand
    include Steps::Narrate
    include Steps::CombatContextUpdate
    include AdventureLoopResolution
    include Mutations
    include Steps::WorldTurn

    include Concerns::NarrationCoordination
    include Concerns::ContextCoordination
    include Concerns::EntryPoints

    attr_reader :adventure, :user, :config, :log, :ai, :sheet, :loop, :run_pipeline,
                :current_cast_roster

    def initialize(adventure:, config:, ai:, log:, sheet:, user: nil, run_pipeline: nil,
      on_progress: nil, on_sheet_update: nil, on_narrative: nil)
      @adventure        = adventure
      @user             = user
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

    def use_game_master?
      return false if @adventure.combat_context&.dig("active")

      FeatureFlag.enabled_for?(:gamemaster_orchestrator, @user)
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

    def restore_roll_pause_inputs(metadata)
      Rolls::RollRequestMetadata.resume_inputs(metadata)
    end

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
      restore_cast_roster_from_paused_loop!
    end

    def restore_cast_roster_from_paused_loop!
      return if @loop.nil?

      stored = @loop.get("cast_roster")
      return if stored.blank? || !stored.is_a?(Hash)

      members = Array(stored["members"]).filter_map do |row|
        next nil unless row.is_a?(Hash)

        actor_sheet_id = Integer(row["actor_sheet_id"], exception: false)
        next nil unless actor_sheet_id&.positive?

        PlayerTurn::CastMember.new(
          adventure_npc_id:  Integer(row["adventure_npc_id"], exception: false),
          actor_sheet_id:    actor_sheet_id,
          name:              row["name"].to_s,
          attitude:          row["attitude"].to_s.presence || "indifferent",
          location_name:     row["location_name"],
        )
      end
      @current_cast_roster = PlayerTurn::CastRoster.new(members: members)
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
