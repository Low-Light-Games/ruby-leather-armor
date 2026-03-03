# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step: Capability Guardrail.
    # Validates that the player actually possesses the spells, feats, or items
    # they are attempting to use. Runs in parallel with MechanicalEvaluation.
    #
    # Two modes controlled by DmConfig guardrail_mode:
    #   "code" (default) — deterministic fuzzy-match against character sheet
    #   "ai"             — AI prompt for holistic validation
    module CapabilityGuardrail
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

      def run_capability_guardrail(intent)
        mode = @config.get("guardrail_mode") || "code"
        return { allowed: true, reason: nil } unless @sheet

        if mode == "ai"
          run_ai_guardrail(intent)
        else
          run_code_guardrail(intent)
        end
      end

      # ------------------------------------------------------------------
      # Code mode: deterministic fuzzy-match
      # ------------------------------------------------------------------

      def run_code_guardrail(intent)
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

      # ------------------------------------------------------------------
      # AI mode: prompt-based holistic validation
      # ------------------------------------------------------------------

      def run_ai_guardrail(intent)
        raw = nil
        prompt_summary = "CapabilityGuardrail: \"#{@log.truncate(intent[:intention])}\""

        char_block = CharacterBlock.full(@sheet)

        system_prompt = PromptRenderer.render("capability_guardrail",
          character_block: char_block)

        request_body = { system_prompt: system_prompt, user_message: intent[:intention] }
        raw = @ai.chat(system_prompt: system_prompt, user_message: intent[:intention],
                        max_tokens: @config.token_budget_for("capability_guardrail"),
                        step_name: "capability_guardrail",
                        model: @config.model_for("capability_guardrail"))
        parsed = @ai.parse_json(raw)
        @log.ai_log!("capability_guardrail", prompt_summary, raw, parsed,
                     parse_status: @ai.last_parse_status, request_body: request_body,
                     model_used: @ai.last_model_used)

        {
          allowed: parsed["allowed"] != false,
          reason: parsed["reason"]
        }
      rescue TokenBudgetExceededError => e
        @log.ai_log_error!("capability_guardrail", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, status: "token_budget_exceeded",
                           model_used: @ai.last_model_used)
        { allowed: true, reason: nil }
      rescue AiError => e
        @log.ai_log_error!("capability_guardrail", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, model_used: @ai.last_model_used)
        { allowed: true, reason: nil }
      end
    end
  end
end
