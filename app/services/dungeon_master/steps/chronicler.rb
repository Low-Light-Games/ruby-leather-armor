# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step: Plot state management and spoiler gating.
    # Produces a "DM Brief" consumed by Narrate and DM Query instead of the raw premise.
    # Updates adventure.plot_state with newly discovered/attempted clues.
    module Chronicler
      private

      def run_chronicler(intent, verdict_outcome: nil, encounter_triggered: false)
        prompt_summary = "Chronicler: plot_relevant action at #{@adventure.current_location&.name || 'unknown'}"

        enriched_premise = @adventure.enriched_premise.presence || @adventure.story.premise
        plot_state = @adventure.plot_state || {}

        all_npcs = StoryNpc.for_adventure(@adventure)
        all_clues = StoryClue.for_adventure(@adventure)
        all_milestones = @adventure.story.story_milestones

        discovered_ids = plot_state["discovered_clues"] || []
        attempted_ids  = plot_state["attempted_clues"] || []
        met_npc_ids    = plot_state["npc_met"] || []

        enriched_world = @adventure.enriched_world || {}
        npc_enrichments = enriched_world["npcs"] || {}

        social_ctx = @adventure.social_context
        traversal_ctx = @adventure.traversal_context
        exploration_ctx = @adventure.exploration_context

        system_prompt = PromptRenderer.render("chronicler",
          enriched_premise: enriched_premise,
          discovered_clues: all_clues.select { |c| discovered_ids.include?(c.id) }.map { |c| { id: c.id, title: c.title } },
          attempted_clues: all_clues.select { |c| attempted_ids.include?(c.id) }.map { |c| { id: c.id, title: c.title } },
          reached_milestones: all_milestones.select { |m| (m.trigger_clue_ids - discovered_ids).empty? && m.trigger_clue_ids.any? }.map { |m| { title: m.title } },
          npcs_met: all_npcs.select { |n| met_npc_ids.include?(n.id) }.map { |n| { name: n.name } },
          intention: intent[:intention],
          primary_context: intent[:primary_context],
          current_location: @adventure.current_location&.name,
          verdict_outcome: verdict_outcome,
          undiscovered_clues: build_undiscovered_clues(all_clues, discovered_ids),
          available_npcs: build_available_npcs(all_npcs, npc_enrichments),
          social_context: social_ctx,
          traversal_context: traversal_ctx,
          exploration_context: exploration_ctx,
          encounter_triggered: encounter_triggered,
        )

        request_body = { system_prompt: system_prompt, user_message: "Evaluate plot state for this action." }

        parsed = timed_ai_call("chronicler", prompt_summary, request_body) do
          raw = @ai.chat(
            system_prompt: system_prompt,
            user_message: "Evaluate plot state for this action.",
            max_tokens: @config.token_budget_for("chronicler"),
            step_name: "chronicler",
            model: @config.model_for("chronicler"),
          )
          [raw, @ai.parse_json(raw)]
        end

        apply_plot_state_updates(parsed["plot_state_updates"] || {})

        adventure_complete = parsed["adventure_complete"] == true
        @loop&.batch_update!(
          new_data: { "adventure_complete" => adventure_complete },
          timeline_entry: { "step" => "chronicler", "summary" => "adventure_complete=#{adventure_complete}", "at" => Time.current.iso8601 })

        guidance = parsed["narration_guidance"].to_s
        forbidden = Array(parsed["forbidden_elements"])
        brief = guidance
        brief += "\nFORBIDDEN — do NOT mention or allude to: #{forbidden.join(', ')}" if forbidden.any?

        {
          dm_brief: brief,
          clues_revealed: parsed["clues_to_reveal"] || [],
          npc_reactions: parsed["npc_reactions"] || {},
          milestones_reached: parsed["milestones_reached"] || [],
        }
      end

      def build_undiscovered_clues(all_clues, discovered_ids)
        all_clues.reject { |c| discovered_ids.include?(c.id) }.map do |c|
          {
            id: c.id,
            title: c.title,
            discovery_method: c.discovery_method,
            difficulty: c.difficulty,
            location_name: c.location&.name,
            npc_name: c.npc&.name,
            prerequisite_ids: c.prerequisite_clue_ids || [],
          }
        end
      end

      def build_available_npcs(all_npcs, npc_enrichments)
        current_loc_id = @adventure.current_location_id
        all_npcs.select { |n| !n.secret || (@adventure.plot_state || {}).dig("npc_met")&.include?(n.id) }
                .select { |n| n.location_id.nil? || n.location_id == current_loc_id }
                .map do |n|
          enrichment = npc_enrichments[n.id.to_s] || {}
          {
            name: n.name,
            enriched_name: enrichment["enriched_name"],
            role: n.role,
            attitude: n.attitude,
            knowledge: enrichment["enriched_knowledge"].presence || n.knowledge,
          }
        end
      end

      def apply_plot_state_updates(updates)
        ps = (@adventure.plot_state || {}).deep_dup

        if (add_clues = updates["discovered_clues_add"]).is_a?(Array)
          ps["discovered_clues"] = ((ps["discovered_clues"] || []) + add_clues.map(&:to_i)).uniq
        end

        if (add_attempted = updates["attempted_clues_add"]).is_a?(Array)
          ps["attempted_clues"] = ((ps["attempted_clues"] || []) + add_attempted.map(&:to_i)).uniq
        end

        if (add_npcs = updates["npc_met_add"]).is_a?(Array)
          ps["npc_met"] = ((ps["npc_met"] || []) + add_npcs.map(&:to_i)).uniq
        end

        if (add_facts = updates["custom_facts_add"]).is_a?(Array)
          ps["custom_facts"] = ((ps["custom_facts"] || []) + add_facts.map(&:to_s)).uniq
        end

        @adventure.update!(plot_state: ps)
      end
    end
  end
end
