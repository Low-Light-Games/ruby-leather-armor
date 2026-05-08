# frozen_string_literal: true

module DungeonMaster
  module Narrative
    class NarratePromptView
      class PromptContext
        attr_reader :pipeline_context, :loop, :combat_state, :time_context,
                    :pacing_text, :directed_play_text, :scene_facts, :outcome_facts

        # rubocop:disable Metrics/ParameterLists
        def initialize(pipeline_context:, loop:, combat_state:, time_context:,
                       pacing_text:, directed_play_text:, scene_facts:, outcome_facts:)
          @pipeline_context   = pipeline_context
          @loop               = loop
          @combat_state       = combat_state
          @time_context       = time_context
          @pacing_text        = pacing_text
          @directed_play_text = directed_play_text
          @scene_facts        = scene_facts
          @outcome_facts      = outcome_facts
        end
        # rubocop:enable Metrics/ParameterLists
      end

      def self.for_narrate(pipeline_engine, pipeline_context, scene_facts:, outcome_facts:)
        adventure   = pipeline_engine.adventure
        sheet       = pipeline_engine.sheet
        live_combat = WorldTurn::LiveContext.merge_live_participants(
          adventure.combat_context || {}, adventure: adventure, sheet: sheet
        )

        context = PromptContext.new(
          pipeline_context:   pipeline_context,
          loop:               pipeline_engine.loop,
          combat_state:       Adventures::CombatState.from_raw(live_combat),
          time_context:       adventure.time_context || {},
          pacing_text:        Ai::PromptHelpers.pacing_instructions(pipeline_engine.config),
          directed_play_text: Ai::PromptHelpers.directed_play_instructions(adventure),
          scene_facts:        Array(scene_facts),
          outcome_facts:      Array(outcome_facts),
        )
        new(context: context)
      end

      def initialize(context:)
        @pipeline_context   = context.pipeline_context
        @loop               = context.loop
        @combat_state       = context.combat_state
        @time_context       = context.time_context
        @pacing_text        = context.pacing_text
        @directed_play_text = context.directed_play_text
        @scene_facts        = context.scene_facts
        @outcome_facts      = context.outcome_facts
      end

      attr_reader :loop, :time_context, :pacing_text, :scene_facts, :outcome_facts

      def directed_play_text
        return "" if @pipeline_context.death_type

        @directed_play_text
      end

      def combined_seed
        @pipeline_context.combined_seed
      end

      def prior_outcomes
        @pipeline_context.prior_outcomes
      end

      def player_action
        @pipeline_context.player_action
      end

      def death_type
        @pipeline_context.death_type
      end

      def combat_facts
        hostiles = @combat_state.participants.filter_map do |participant|
          next unless participant.hostile? && participant.hp.is_a?(Numeric)

          {
            "name"   => participant.name,
            "hp"     => participant.hp,
            "max_hp" => participant.max_hp,
            "alive"  => participant.alive?,
          }
        end

        {
          "active"            => @combat_state.active?,
          "hostiles"          => hostiles,
          "any_hostile_alive" => hostiles.any? { |hostile| hostile["alive"] == true },
        }
      end
    end
  end
end
