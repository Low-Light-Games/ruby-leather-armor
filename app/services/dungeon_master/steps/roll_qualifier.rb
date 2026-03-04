# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step: Roll Qualifier.
    # Runs after each MechanicalEvaluation domain iteration when player_rolls
    # are present. Determines:
    #   1. Situational modifiers (advantage, circumstance bonuses from terrain,
    #      flanking, high ground, surprise, etc.)
    #   2. Take 10 / Take 20 eligibility (requires no duress, no threats,
    #      no time pressure, and no dangerous failure consequences for Take 20)
    #
    # Uses broader context than MechanicalEvaluation to judge the character's
    # situational state. Context scope is configurable via the
    # `roll_qualifier_scope` DmConfig toggle.
    module RollQualifier
      SCOPE_CONTEXTS = {
        "all"              => %w[combat exploration social traversal rest inventory],
        "domain"           => :domain_only,
        "dynamic"          => :dynamic,
        "social_traversal" => %w[social traversal],
        "traversal_combat" => %w[traversal combat],
        "scene"            => []
      }.freeze

      VALID_SCOPES = SCOPE_CONTEXTS.keys.freeze

      private

      def run_roll_qualifier(evaluation, intent)
        rolls = evaluation[:player_rolls]
        return evaluation if rolls.empty?

        scope = @config.get("roll_qualifier_scope") || "domain"
        scope = "domain" unless VALID_SCOPES.include?(scope)

        context_names = resolve_qualifier_contexts(scope, evaluation)
        context_block = build_qualifier_context_block(context_names)

        raw = nil
        prompt_summary = "RollQualifier [#{evaluation[:domain]}]: " \
                         "#{rolls.size} roll(s), scope=#{scope}"

        system_prompt = PromptRenderer.render("roll_qualifier",
          domain: evaluation[:domain],
          mechanical_summary: evaluation[:mechanical_summary],
          rolls_json: rolls.to_json,
          context_block: context_block,
          scene_summary: @adventure.scene_summary.presence || "(no scene summary)")

        request_body = { system_prompt: system_prompt, user_message: intent[:intention] }
        raw = @ai.chat(system_prompt: system_prompt, user_message: intent[:intention],
                        max_tokens: @config.token_budget_for("roll_qualifier"),
                        step_name: "roll_qualifier",
                        model: @config.model_for("roll_qualifier"))
        parsed = @ai.parse_json(raw)
        @log.ai_log!("roll_qualifier", prompt_summary, raw, parsed,
                     parse_status: @ai.last_parse_status, request_body: request_body,
                     model_used: @ai.last_model_used)

        apply_qualifier_results(evaluation, parsed)
      rescue TokenBudgetExceededError => e
        @log.ai_log_error!("roll_qualifier", prompt_summary || "RollQualifier failed", e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, status: "token_budget_exceeded",
                           model_used: @ai.last_model_used)
        evaluation
      rescue AiError => e
        @log.ai_log_error!("roll_qualifier", prompt_summary || "RollQualifier failed", e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body,
                           model_used: @ai.last_model_used)
        evaluation
      end

      def resolve_qualifier_contexts(scope, evaluation)
        case SCOPE_CONTEXTS[scope]
        when :dynamic
          hints = Array(evaluation[:qualifier_context_hints])
          hints.empty? ? [evaluation[:domain]] : hints
        when :domain_only
          [evaluation[:domain]]
        when Array
          SCOPE_CONTEXTS[scope]
        else
          [evaluation[:domain]]
        end
      end

      def build_qualifier_context_block(context_names)
        parts = context_names.filter_map do |field|
          ctx = @adventure.send("#{field}_context") rescue nil
          "=== #{field.upcase} CONTEXT ===\n#{ctx.to_json}" if ctx.present?
        end
        parts.any? ? parts.join("\n\n") : "(no relevant context data available)"
      end

      def apply_qualifier_results(evaluation, parsed)
        qualifications = Array(parsed["qualifications"])
        return evaluation if qualifications.empty?

        qual_by_skill = qualifications.index_by { |q| q["skill"] }

        qualified_rolls = evaluation[:player_rolls].map do |roll|
          qual = qual_by_skill[roll[:skill].to_s]
          next roll unless qual

          roll.merge(
            take_10_eligible: qual["take_10_eligible"] == true,
            take_20_eligible: qual["take_20_eligible"] == true,
            take_10_value: qual["take_10_value"],
            take_20_value: qual["take_20_value"],
            situational_modifiers: Array(qual["situational_modifiers"]).map(&:deep_symbolize_keys)
          )
        end

        evaluation.merge(player_rolls: qualified_rolls)
      end
    end
  end
end
