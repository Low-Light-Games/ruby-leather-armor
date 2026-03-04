# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step: Mechanical Evaluation loop.
    # Runs once per affected context (combat, traversal, social) to determine
    # what rolls and NPC actions are required. Each iteration receives the
    # summaries of preceding evaluations for cross-context awareness.
    #
    # Renamed from the original "Ruling" step — this step focuses purely on
    # identifying required mechanics (rolls, NPC reactions, consequences).
    # Capability validation is handled by the parallel CapabilityGuardrail.
    module MechanicalEvaluation
      private

      def run_mechanical_evaluation_loop(intent)
        contexts = intent[:affected_contexts]
        contexts = [intent[:primary_context]] if contexts.empty? && intent[:primary_context].present?
        raise AiError, "MechanicalEvaluation reached with no affected contexts and no primary context" if contexts.empty?

        primary = intent[:primary_context]
        if primary && contexts.include?(primary)
          contexts = [primary] + (contexts - [primary])
        end

        previous_summaries = []
        evaluations = []
        current_raw = nil
        current_request_body = nil
        current_prompt_summary = nil

        contexts.each_with_index do |domain, idx|
          current_raw = nil
          current_request_body = nil
          current_prompt_summary = "MechEval [#{domain}] iteration #{idx + 1}/#{contexts.size}: " \
                                   "\"#{@log.truncate(intent[:intention])}\""

          rules_text = Rules.fetch(*intent[:rules_needed])
          char_block = CharacterBlock.for(@sheet, category: domain)
          micro_ctx  = @adventure.send("#{domain}_context")
          creature_stats = CharacterBlock.creature_stats_for(@adventure)

          domain_instructions = PromptRenderer.render_partial("mechanical_evaluation/_#{domain}")

          system_prompt = PromptRenderer.render("mechanical_evaluation",
            domain: domain,
            character_block: char_block,
            micro_context: micro_ctx.present? ? micro_ctx.to_json : nil,
            creature_stats: creature_stats,
            previous_summaries: previous_summaries,
            rules_text: rules_text,
            domain_instructions: domain_instructions)

          current_request_body = { system_prompt: system_prompt, user_message: intent[:intention] }
          current_raw = @ai.chat(system_prompt: system_prompt, user_message: intent[:intention],
                                  max_tokens: @config.token_budget_for("mechanical_evaluation"),
                                  step_name: "mechanical_evaluation",
                                  model: @config.model_for("mechanical_evaluation"))
          parsed = @ai.parse_json(current_raw)
          @log.ai_log!("mechanical_evaluation", current_prompt_summary, current_raw, parsed,
                       parse_status: @ai.last_parse_status, request_body: current_request_body,
                       model_used: @ai.last_model_used)

          evaluation = {
            domain: domain,
            player_rolls: Array(parsed["player_rolls"]).map(&:deep_symbolize_keys),
            npc_actions: Array(parsed["npc_actions"]).map(&:deep_symbolize_keys),
            consequences: Array(parsed["consequences"]).map(&:deep_symbolize_keys),
            mechanical_summary: parsed["mechanical_summary"] || parsed["ruling_summary"] || "",
            qualifier_context_hints: Array(parsed["qualifier_context_hints"])
          }

          evaluation = run_roll_qualifier(evaluation, intent)

          previous_summaries << "[#{domain.upcase}] #{evaluation[:mechanical_summary]}"
          evaluations << evaluation
        end

        evaluations
      rescue TokenBudgetExceededError => e
        @log.ai_log_error!("mechanical_evaluation", current_prompt_summary || "MechanicalEvaluation loop failed", e,
                           raw_response: current_raw || @ai.last_failed_raw_response,
                           request_body: current_request_body,
                           status: "token_budget_exceeded",
                           model_used: @ai.last_model_used)
        raise
      rescue AiError => e
        @log.ai_log_error!("mechanical_evaluation", current_prompt_summary || "MechanicalEvaluation loop failed", e,
                           raw_response: current_raw || @ai.last_failed_raw_response,
                           request_body: current_request_body,
                           model_used: @ai.last_model_used)
        raise
      end

      def merge_mechanical_evaluations(evaluations)
        {
          player_rolls: evaluations.flat_map { |e| e[:player_rolls] },
          npc_actions: evaluations.flat_map { |e| e[:npc_actions] },
          consequences: evaluations.flat_map { |e| e[:consequences] },
          mechanical_summaries: evaluations.map { |e| "[#{e[:domain].upcase}] #{e[:mechanical_summary]}" }
        }
      end
    end
  end
end
