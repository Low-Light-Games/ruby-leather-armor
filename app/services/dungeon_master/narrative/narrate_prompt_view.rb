# frozen_string_literal: true

module DungeonMaster
  module Narrative
    # Single ERB root for `narrate.text.erb`: loop, time, pacing, and PipelineContext fields.
    class NarratePromptView
      BuildContext = Struct.new(
        :pipeline_context, :loop, :combat_context, :time_context, :pacing_text, :directed_play_text,
        keyword_init: true
      )

      def self.for_narrate(pipeline_engine, pipeline_context)
        base_combat_context = pipeline_engine.adventure.combat_context || {}
        live_combat_context = WorldTurn::LiveContext.merge_live_participants(
          base_combat_context,
          adventure: pipeline_engine.adventure,
          sheet: pipeline_engine.sheet
        )

        context = BuildContext.new(
          pipeline_context:   pipeline_context,
          loop:               pipeline_engine.loop,
          combat_context:     live_combat_context,
          time_context:       pipeline_engine.adventure.time_context || {},
          pacing_text:        PromptHelpers.pacing_instructions(pipeline_engine.config),
          directed_play_text: PromptHelpers.directed_play_instructions(pipeline_engine.adventure)
        )
        new(context: context)
      end

      def initialize(context:)
        @pipeline_context = context.pipeline_context
        @loop = context.loop
        @combat_context = context.combat_context
        @time_context = context.time_context
        @pacing_text = context.pacing_text
        @directed_play_text = context.directed_play_text
      end

      attr_reader :loop, :time_context, :pacing_text

      # Suppressed for terminal outcomes: a character who just died or collapsed
      # cannot be offered "what do you do next?" choices.
      def directed_play_text
        return "" if @pipeline_context.death_type

        @directed_play_text
      end

      def dm_brief
        @pipeline_context.dm_brief
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
        hostiles = Array(@combat_context["participants"]).filter_map do |row|
          next if row["type"].to_s == "player"

          hp = row["hp"]
          next unless hp.is_a?(Numeric)

          {
            "name" => row["name"].to_s,
            "hp" => hp,
            "max_hp" => row["max_hp"],
            "alive" => hp.positive?
          }
        end

        {
          "active" => @combat_context["active"] == true,
          "hostiles" => hostiles,
          "any_hostile_alive" => hostiles.any? { |hostile| hostile["alive"] == true }
        }
      end
    end
  end
end
