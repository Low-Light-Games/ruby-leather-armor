# frozen_string_literal: true

module DungeonMaster
  module Lore
    # Runs Loremaster once at adventure creation to seed the narrative
    # facts store. Input sources, failure contract, and placement
    # rationale: docs/pipeline_steps.md Decision 37.
    class SeedFromAdventure
      SEED_MODEL_KEY = "loremaster"

      def self.call(adventure:, user: nil, ai: nil, log: nil, config: nil)
        new(adventure: adventure, user: user, ai: ai, log: log, config: config).call
      end

      def initialize(adventure:, user: nil, ai: nil, log: nil, config: nil)
        @adventure = adventure
        @user      = user || adventure.user
        @config    = config || DmConfig.instance
        @ai        = ai || DungeonMaster::AiClient.new(@config)
        @log       = log || DungeonMaster::Logging.new(
          adventure: @adventure, user: @user, dm_service: "standard"
        )
      end

      def call
        system_prompt = DungeonMaster::Steps::Loremaster.render_seed_prompt(
          premise:               premise_text,
          enriched_world:        enriched_world_text,
          opening_narrative:     opening_narrative_text,
          initial_contexts_text: initial_contexts_text,
          npcs_text:             npcs_text,
          clues_text:            clues_text,
          locations_text:        locations_text,
        )

        result = run_loremaster_seed_call(system_prompt)
        return FactsChangeSet.empty if result.nil?

        DungeonMaster::Lore::ApplyResults.call(
          adventure: @adventure,
          loop:      nil,
          log:       @log,
          ai:        @ai,
          result:    result,
          source:    "seed",
        )
      rescue StandardError => e
        handle_seed_failure(e)
        FactsChangeSet.empty
      end

      private

      def run_loremaster_seed_call(system_prompt)
        prompt_summary = "Loremaster seed — adventure ##{@adventure.id}"

        @log.timed_chat_call(SEED_MODEL_KEY, prompt_summary, ai: @ai) do
          raw = @ai.chat(
            system_prompt: system_prompt,
            user_message:  "Seed the narrative facts store for this adventure.",
            max_tokens:    @config.token_budget_for(SEED_MODEL_KEY),
            step_name:     SEED_MODEL_KEY,
            model:         @config.model_for(SEED_MODEL_KEY),
          )
          [raw, @ai.parse_json(raw)]
        end
      end

      def handle_seed_failure(exception)
        @log.report_error(exception, context: {
          step: "loremaster_seed",
          adventure_id: @adventure&.id,
          source: "seed_from_adventure",
        })
        @log.play_log!(
          "seed_failure",
          "Loremaster seed failed: #{exception.class}",
          parsed_response: { error: exception.message.to_s.truncate(500) },
        )
      end

      # --- Seed-input assembly -------------------------------------------

      def premise_text
        @adventure.story&.premise.to_s
      end

      def enriched_world_text
        ew = @adventure.enriched_world
        return "(none)" if ew.blank?

        ew.is_a?(String) ? ew : ew.to_json
      end

      def opening_narrative_text
        first = @adventure.adventure_messages.chronological.first
        first&.content.to_s.presence || "(no opening narrative)"
      end

      def initial_contexts_text
        block = DungeonMaster::PromptHelpers.build_micro_contexts_block(@adventure)
        block.presence || "(no initial micro-contexts)"
      end

      def npcs_text
        rows = StoryNpc.for_adventure(@adventure).ordered_by_id.map do |npc|
          parts = ["- #{npc.name} (role: #{npc.role}, attitude: #{npc.attitude})"]
          parts << "  description: #{npc.description}" if npc.description.present?
          parts.join("\n")
        end
        rows.any? ? rows.join("\n") : "(none)"
      end

      def clues_text
        rows = StoryClue.for_adventure(@adventure).ordered_by_id.map do |clue|
          parts = ["- #{clue.title} (discovery: #{clue.discovery_method}, difficulty: #{clue.difficulty})"]
          parts << "  description: #{clue.description}" if clue.description.present?
          parts.join("\n")
        end
        rows.any? ? rows.join("\n") : "(none)"
      end

      def locations_text
        locations = @adventure.story&.story_locations&.order(:id).to_a
        rows = locations.map do |loc|
          parts = ["- #{loc.name}"]
          parts << "  description: #{loc.description}" if loc.description.present?
          parts.join("\n")
        end
        rows.any? ? rows.join("\n") : "(none)"
      end
    end
  end
end
