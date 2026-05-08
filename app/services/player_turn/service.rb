# frozen_string_literal: true

module PlayerTurn
  class Service
    def initialize(adventure, user:)
      @runtime = EntryRuntime.new(adventure: adventure, user: user)
      @prompt_execution = EntryServices::PromptExecution.new(runtime: @runtime)
      @resume_execution = EntryServices::ResumePipelineExecution.new(runtime: @runtime)
    end

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
        content: Adventures::RollResultsText.format(roll_results_from_player),
        message_type: "roll_result",
        metadata: { rolls: roll_results_from_player })
    end

    def execute_prompt(player_input, player_message_id:)
      prompt_execution.call(player_input: player_input, player_message_id: player_message_id)
    end

    def execute_rolls(roll_results_text, player_message_id:)
      resume_execution.call(player_message_id: player_message_id) do
        metadata = Adventures::MechanicalState.latest_roll_metadata(runtime.adventure)
        submitted_rolls = runtime.adventure.adventure_messages.find(player_message_id).metadata&.dig("rolls")
        runtime.resume_or_start_pipeline!(metadata, roll_results_text)
        runtime.ensure_run_pipeline!
        Timing.run(runtime.log) do
          runtime.pipeline_engine.run_rolls(roll_results_text, metadata, submitted_rolls: submitted_rolls)
        end
      end
    end

    def execute_initiative(player_initiative, player_message_id:)
      resume_execution.call(player_message_id: player_message_id) do
        metadata = Adventures::MechanicalState.latest_initiative_metadata(runtime.adventure)
        resume_content = "Initiative: #{player_initiative}"
        runtime.resume_or_start_pipeline!(metadata, resume_content)
        runtime.ensure_run_pipeline!
        Timing.run(runtime.log) do
          runtime.pipeline_engine.run_initiative(player_initiative.to_i, metadata)
        end
      end
    end

    def self.message_json(message, admin: false)
      Adventures::MessageSerializer.as_json(message, admin: admin)
    end

    private

    attr_reader :runtime, :prompt_execution, :resume_execution

    def enforce_pipeline_policy!
      runtime.enforce_pipeline_policy!
    end
  end
end
