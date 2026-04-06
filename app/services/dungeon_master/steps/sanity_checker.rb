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
    #
    # When both run together (full gate with sheet), they use Node POST /fan_out
    # — no Ruby Thread.new.
    module SanityChecker
      private

      # World + capability in one evaluator round-trip (CoreResolver#run_sanity_gate).
      def run_sanity_gate_fan_out(intent)
        evaluator_url = ENV.fetch("EVALUATOR_URL", "http://evaluator:3001")
        text = intent[:intention]
        prompts = [sanity_checker_world_evaluator_prompt(intent)]
        prompts << sanity_checker_capability_evaluator_prompt(intent) if @sheet

        results = call_evaluator!("#{evaluator_url}/fan_out", prompts, text, phase: "sanity_gate")

        world = parse_world_from_evaluator_result(results[0])
        capability = if @sheet
                       parse_capability_from_evaluator_result(results[1])
                     else
                       { allowed: true, reason: nil }
                     end
        [world, capability]
      end

      def sanity_checker_world_evaluator_prompt(intent)
        micro_contexts = PromptHelpers.all_micro_contexts(@adventure)
        npc_names = @adventure.story.story_npcs.pluck(:name)

        system_prompt = PromptRenderer.render("sanity_checker_world",
          scene_summary: @adventure.scene_summary,
          scene_history: Array(@adventure.scene_history),
          micro_contexts: micro_contexts,
          npc_names: npc_names)

        {
          system_prompt: system_prompt,
          user_message:  intent[:intention],
          model:         @config.model_for("sanity_checker_world"),
          max_tokens:    @config.token_budget_for("sanity_checker_world"),
          meta:          { step: "sanity_checker_world" }
        }
      end

      def sanity_checker_capability_evaluator_prompt(intent)
        char_block = CharacterBlock.full(@sheet)
        ds = @sheet.derived_stats || {}
        restrictions = Array(ds["condition_restrictions"])

        system_prompt = PromptRenderer.render("sanity_checker",
          character_block: char_block,
          condition_restrictions: restrictions)

        {
          system_prompt: system_prompt,
          user_message:  intent[:intention],
          model:         @config.model_for("sanity_checker"),
          max_tokens:    @config.token_budget_for("sanity_checker"),
          meta:          { step: "sanity_checker" }
        }
      end

      def parse_world_from_evaluator_result(result)
        parsed = result["parsed_response"] || {}
        {
          consistent: parsed["consistent"] != false,
          reason: parsed["reason"],
          dm_message: parsed["dm_message"],
          referenced_entities: Array(parsed["referenced_entities"])
        }
      end

      def parse_capability_from_evaluator_result(result)
        parsed = result["parsed_response"] || {}
        { allowed: parsed["allowed"] != false, reason: parsed["reason"] }
      end

      # ------------------------------------------------------------------
      # Sub-task A: Capability Check (spells / feats / items vs sheet)
      # ------------------------------------------------------------------

      def run_capability_check(intent)
        return { allowed: true, reason: nil } unless @sheet

        prompt_summary = "SanityChecker/capability: \"#{@log.truncate(intent[:intention])}\""
        char_block = CharacterBlock.full(@sheet)
        ds = @sheet.derived_stats || {}
        restrictions = Array(ds["condition_restrictions"])

        system_prompt = PromptRenderer.render("sanity_checker",
          character_block: char_block,
          condition_restrictions: restrictions)

        request_body = { system_prompt: system_prompt, user_message: intent[:intention] }

        parsed = timed_ai_call("sanity_checker", prompt_summary, request_body) do
          raw = @ai.chat(system_prompt: system_prompt, user_message: intent[:intention],
                          max_tokens: @config.token_budget_for("sanity_checker"),
                          step_name: "sanity_checker",
                          model: @config.model_for("sanity_checker"))
          [raw, @ai.parse_json(raw)]
        end

        { allowed: parsed["allowed"] != false, reason: parsed["reason"] }
      end

      # ------------------------------------------------------------------
      # Sub-task B: World Consistency Check (scene state validation)
      # ------------------------------------------------------------------

      def run_world_consistency_check(intent)
        prompt_summary = "SanityChecker/world: \"#{@log.truncate(intent[:intention])}\""

        micro_contexts = PromptHelpers.all_micro_contexts(@adventure)
        npc_names = @adventure.story.story_npcs.pluck(:name)

        system_prompt = PromptRenderer.render("sanity_checker_world",
          scene_summary: @adventure.scene_summary,
          scene_history: Array(@adventure.scene_history),
          micro_contexts: micro_contexts,
          npc_names: npc_names)

        request_body = { system_prompt: system_prompt, user_message: intent[:intention] }

        parsed = timed_ai_call("sanity_checker_world", prompt_summary, request_body) do
          raw = @ai.chat(system_prompt: system_prompt, user_message: intent[:intention],
                          max_tokens: @config.token_budget_for("sanity_checker_world"),
                          step_name: "sanity_checker_world",
                          model: @config.model_for("sanity_checker_world"))
          [raw, @ai.parse_json(raw)]
        end

        {
          consistent: parsed["consistent"] != false,
          reason: parsed["reason"],
          dm_message: parsed["dm_message"],
          referenced_entities: Array(parsed["referenced_entities"])
        }
      end
    end
  end
end
