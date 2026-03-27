# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step: SanityChecker.
    #
    # Two sub-checks under one umbrella:
    #
    #   A) Capability Check — validates that the player possesses the spells,
    #      feats, or items they intend to *use*. Runs in parallel with
    #      MechanicalEvaluation inside the full gate (needs_mechanics only).
    #      AI-driven: the sheet is structured data, but understanding *intent*
    #      is a natural-language problem. Regex/fuzzy-match cannot distinguish
    #      "cast fireball" (requires the spell) from "buy a scroll of fireball"
    #      (requires gold, not the spell). The model reads the sentence and the
    #      sheet together.
    #
    #   B) World Consistency Check — validates that the entities, targets, or
    #      objects the player references actually exist in the current scene.
    #      AI-only for the same reason: scene state lives in prose context.
    #      Runs ALWAYS (via full gate or standalone).
    module SanityChecker
      private

      # ------------------------------------------------------------------
      # Standalone: single-call capability check (skip_world_sanity_check path)
      # ------------------------------------------------------------------

      def run_capability_check(intent)
        return { allowed: true, reason: nil } unless @sheet

        prompt = build_capability_prompt(intent)
        prompt_summary = "SanityChecker/capability: \"#{@log.truncate(intent[:intention])}\""
        request_body = { system_prompt: prompt[:system_prompt], user_message: prompt[:user_message] }

        parsed = timed_ai_call("sanity_checker", prompt_summary, request_body) do
          raw = @ai.chat(system_prompt: prompt[:system_prompt], user_message: prompt[:user_message],
                          max_tokens: prompt[:max_tokens], step_name: "sanity_checker",
                          model: prompt[:model])
          [raw, @ai.parse_json(raw)]
        end

        { allowed: parsed["allowed"] != false, reason: parsed["reason"] }
      end

      # ------------------------------------------------------------------
      # Standalone: single-call world consistency check (non-mechanical path)
      # ------------------------------------------------------------------

      def run_world_consistency_check(intent)
        prompt = build_world_check_prompt(intent)
        prompt_summary = "SanityChecker/world: \"#{@log.truncate(intent[:intention])}\""
        request_body = { system_prompt: prompt[:system_prompt], user_message: prompt[:user_message] }

        parsed = timed_ai_call("sanity_checker_world", prompt_summary, request_body) do
          raw = @ai.chat(system_prompt: prompt[:system_prompt], user_message: prompt[:user_message],
                          max_tokens: prompt[:max_tokens], step_name: "sanity_checker_world",
                          model: prompt[:model])
          [raw, @ai.parse_json(raw)]
        end

        {
          consistent:          parsed["consistent"] != false,
          reason:              parsed["reason"],
          dm_message:          parsed["dm_message"],
          referenced_entities: Array(parsed["referenced_entities"])
        }
      end

      # ------------------------------------------------------------------
      # Prompt builders (shared by solo paths above and fan-out gate below)
      # ------------------------------------------------------------------

      def build_world_check_prompt(intent)
        micro_contexts = PromptHelpers.all_micro_contexts(@adventure)
        npc_names = @adventure.story.story_npcs.pluck(:name)

        system_prompt = PromptRenderer.render("sanity_checker_world",
          scene_summary:  @adventure.scene_summary,
          scene_history:  Array(@adventure.scene_history),
          micro_contexts: micro_contexts,
          npc_names:      npc_names)

        {
          system_prompt: system_prompt,
          user_message:  intent[:intention],
          model:         @config.model_for("sanity_checker_world"),
          max_tokens:    @config.token_budget_for("sanity_checker_world"),
          meta:          { step: "sanity_checker_world" }
        }
      end

      def build_capability_prompt(intent)
        char_block   = CharacterBlock.full(@sheet)
        ds           = @sheet.derived_stats || {}
        restrictions = Array(ds["condition_restrictions"])

        system_prompt = PromptRenderer.render("sanity_checker",
          character_block:       char_block,
          condition_restrictions: restrictions)

        {
          system_prompt: system_prompt,
          user_message:  intent[:intention],
          model:         @config.model_for("sanity_checker"),
          max_tokens:    @config.token_budget_for("sanity_checker"),
          meta:          { step: "sanity_checker" }
        }
      end
    end
  end
end
