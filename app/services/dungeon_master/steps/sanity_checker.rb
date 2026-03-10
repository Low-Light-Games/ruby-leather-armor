# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step: SanityChecker.
    #
    # Two sub-checks under one umbrella:
    #
    #   A) Capability Check — validates that the player possesses the spells,
    #      feats, or items they reference. Runs in parallel with MechanicalEvaluation
    #      inside the full gate (only when needs_mechanics is true).
    #      Two modes controlled by DmConfig guardrail_mode:
    #        "code" (default) — deterministic fuzzy-match against character sheet
    #        "ai"             — AI prompt for holistic validation
    #
    #   B) World Consistency Check — validates that the entities, targets, or
    #      objects the player references actually exist in the current scene.
    #      AI-only step. Runs ALWAYS (via full gate or standalone).
    module SanityChecker
      SPELL_PATTERNS = [
        /\bcast(?:s|ing)?\s+(.+?)(?:\s+(?:to|on|at|for|and|from|into|through|using|against)\b|[.,!?]|$)/i,
        /\buse(?:s|d)?\s+(?:the\s+)?spell\s+(.+?)(?:\s+(?:to|on|at|for|and)\b|[.,!?]|$)/i,
      ].freeze

      FEAT_PATTERNS = [
        /\buse(?:s|d)?\s+(?:the\s+)?(?:feat|ability)\s+(.+?)(?:\s+(?:to|on|at|for|and)\b|[.,!?]|$)/i,
        /\bactivate(?:s|d)?\s+(.+?)(?:\s+(?:to|on|at|for|and)\b|[.,!?]|$)/i,
      ].freeze

      ITEM_PATTERNS = [
        /\buse(?:s|d)?\s+(?:the\s+)?(?:my\s+)?(?:item\s+)?(.+?)(?:\s+(?:to|on|at|for|and)\b|[.,!?]|$)/i,
        /\bdrink(?:s|ing)?\s+(?:a\s+|the\s+|my\s+)?(.+?)(?:\s+(?:to|on|at|for|and)\b|[.,!?]|$)/i,
        /\bequip(?:s|ping)?\s+(?:the\s+|my\s+)?(.+?)(?:\s+(?:to|on|at|for|and)\b|[.,!?]|$)/i,
      ].freeze

      private

      # ------------------------------------------------------------------
      # Sub-task A: Capability Check (spells / feats / items vs sheet)
      # ------------------------------------------------------------------

      def run_capability_check(intent)
        mode = @config.get("guardrail_mode") || "code"
        return { allowed: true, reason: nil } unless @sheet

        if mode == "ai"
          run_ai_capability_check(intent)
        else
          run_code_capability_check(intent)
        end
      end

      def run_code_capability_check(intent)
        intention = intent[:intention].to_s

        sheet_spells = load_sheet_spell_names
        sheet_feats  = load_sheet_feat_names
        sheet_items  = load_sheet_item_names

        spell_check = check_capabilities(intention, SPELL_PATTERNS, sheet_spells, "spell")
        return spell_check unless spell_check[:allowed]

        feat_check = check_capabilities(intention, FEAT_PATTERNS, sheet_feats, "feat")
        return feat_check unless feat_check[:allowed]

        item_check = check_capabilities(intention, ITEM_PATTERNS, sheet_items, "item")
        return item_check unless item_check[:allowed]

        { allowed: true, reason: nil }
      end

      def check_capabilities(intention, patterns, known_names, kind)
        return { allowed: true, reason: nil } if known_names.empty?

        patterns.each do |pattern|
          next unless intention.match(pattern)

          referenced_name = Regexp.last_match(1).strip
          next if referenced_name.blank? || referenced_name.length < 2

          match = fuzzy_match?(referenced_name, known_names)
          unless match
            return {
              allowed: false,
              reason: "Character does not have the #{kind} '#{referenced_name}' on their sheet."
            }
          end
        end

        { allowed: true, reason: nil }
      end

      def fuzzy_match?(candidate, known_names)
        candidate_down = candidate.downcase
        known_names.any? do |name|
          name_down = name.downcase
          name_down == candidate_down ||
            name_down.include?(candidate_down) ||
            candidate_down.include?(name_down)
        end
      end

      def load_sheet_spell_names
        @sheet.adventure_sheet_spells
              .includes(:spell_definition)
              .filter_map { |s| s.spell_definition&.name }
      end

      def load_sheet_feat_names
        @sheet.adventure_sheet_feats
              .includes(:feat_definition)
              .filter_map { |f| f.feat_definition&.name }
      end

      def load_sheet_item_names
        @sheet.adventure_sheet_items
              .includes(:item_definition)
              .filter_map { |i| i.item_definition&.name }
      end

      def run_ai_capability_check(intent)
        prompt_summary = "SanityChecker/capability: \"#{@log.truncate(intent[:intention])}\""
        char_block = CharacterBlock.full(@sheet)

        system_prompt = PromptRenderer.render("sanity_checker",
          character_block: char_block)

        request_body = { system_prompt: system_prompt, user_message: intent[:intention] }

        parsed = timed_ai_call("sanity_checker", prompt_summary, request_body) do
          raw = @ai.chat(system_prompt: system_prompt, user_message: intent[:intention],
                          max_tokens: @config.token_budget_for("sanity_checker"),
                          step_name: "sanity_checker",
                          model: @config.model_for("sanity_checker"))
          [raw, @ai.parse_json(raw)]
        end

        { allowed: parsed["allowed"] != false, reason: parsed["reason"] }
      rescue TokenBudgetExceededError, AiError
        { allowed: true, reason: nil }
      end

      # ------------------------------------------------------------------
      # Sub-task B: World Consistency Check (scene state validation)
      # ------------------------------------------------------------------

      def run_world_consistency_check(intent)
        prompt_summary = "SanityChecker/world: \"#{@log.truncate(intent[:intention])}\""

        micro_contexts = PromptHelpers.all_micro_contexts(@adventure)
        scene_history = Array(@adventure.try(:scene_history))
        scene_history_block = if scene_history.any?
                                scene_history.map { |h| "- #{h['summary']}" }.join("\n")
                              else
                                "(no prior scene history)"
                              end

        npc_names = begin
          @adventure.story.story_npcs.pluck(:name)
        rescue
          []
        end

        system_prompt = PromptRenderer.render("sanity_checker_world",
          scene_summary: @adventure.scene_summary || "(no scene established yet)",
          scene_history_block: scene_history_block,
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
          referenced_entities: Array(parsed["referenced_entities"])
        }
      rescue TokenBudgetExceededError, AiError
        { consistent: true, reason: nil, referenced_entities: [] }
      end
    end
  end
end
