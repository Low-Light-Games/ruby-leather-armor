# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step 2: Interpret the player's intention.
    # Determines whether mechanics are needed, which contexts are affected,
    # and which rules to fetch.
    module Intent
      private

      def run_intent(sanitized_input)
        raw = nil
        prompt_summary = "Intent: \"#{@log.truncate(sanitized_input)}\""
        manifest = Rules.manifest

        system_prompt = PromptRenderer.render("intent",
          contexts: PromptHelpers.build_micro_contexts_block(@adventure),
          manifest_text: PromptHelpers.format_manifest(manifest),
          locations_text: format_story_locations,
          plot_manifest: build_plot_manifest)
        request_body = { system_prompt: system_prompt, user_message: sanitized_input }

        raw = @ai.chat(system_prompt: system_prompt, user_message: sanitized_input,
                        max_tokens: @config.token_budget_for("intent"), step_name: "intent",
                        model: @config.model_for("intent"))
        parsed = @ai.parse_json(raw)
        @log.ai_log!("intent", prompt_summary, raw, parsed,
                     parse_status: @ai.last_parse_status, request_body: request_body,
                     model_used: @ai.last_model_used)

        {
          intention: parsed["intention"] || sanitized_input,
          needs_mechanics: parsed["needs_mechanics"] == true,
          time_spanning: parsed["time_spanning"] == true,
          time_span_type: parsed["time_span_type"],
          destination: parsed["destination"],
          estimated_hours: parsed["estimated_hours"]&.to_f,
          affected_contexts: Array(parsed["affected_contexts"]).map(&:to_s) & %w[combat traversal social exploration rest inventory],
          primary_context: parsed["primary_context"]&.to_s,
          rules_needed: Array(parsed["rules_needed"]).map(&:to_s),
          transition: parsed["transition"],
          macro_significant: parsed["macro_significant"] == true,
          plot_relevant: parsed["plot_relevant"] == true
        }
      rescue TokenBudgetExceededError => e
        @log.ai_log_error!("intent", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, status: "token_budget_exceeded",
                           model_used: @ai.last_model_used)
        raise
      rescue AiError => e
        @log.ai_log_error!("intent", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, model_used: @ai.last_model_used)
        raise
      end

      def build_plot_manifest
        story = @adventure.story
        npcs = StoryNpc.for_adventure(@adventure).where(secret: false)
        clues = StoryClue.for_adventure(@adventure)
        discovered = (@adventure.plot_state || {})["discovered_clues"] || []
        undiscovered = clues.reject { |c| discovered.include?(c.id) }

        return nil if npcs.empty? && undiscovered.empty?

        lines = []

        loc_names = undiscovered.filter_map { |c| c.location&.name }.uniq
        lines << "Locations with discoverable content: #{loc_names.join(', ')}" if loc_names.any?

        npc_names = npcs.filter_map(&:name).uniq
        lines << "NPCs with plot knowledge: #{npc_names.join(', ')}" if npc_names.any?

        methods = undiscovered.map(&:discovery_method).uniq
        lines << "Discovery methods with content: #{methods.join(', ')}" if methods.any?

        lines.join("\n")
      end

      def format_story_locations
        locs = @adventure.story.story_locations.includes(:connections_from, :connections_to)
        return "(no locations defined for this story)" if locs.empty?

        current = @adventure.current_location
        lines = locs.map do |loc|
          marker = loc.id == current&.id ? " [CURRENT]" : ""
          marker += " [START]" if loc.starting
          conns = loc.connections.map do |c|
            other = c.other_location(loc)
            "#{other.name} (#{c.distance_miles} mi, #{c.terrain_type})"
          end
          "- #{loc.name}#{marker}: #{loc.description&.truncate(80) || '(no description)'}#{conns.any? ? "\n  Connects to: #{conns.join(', ')}" : ''}"
        end
        lines.join("\n")
      end
    end
  end
end
