# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step 3: Ruling loop.
    # Runs once per affected context (combat, traversal, social) to determine
    # what rolls and NPC actions are required. Each iteration receives the
    # summaries of preceding rulings for cross-context awareness.
    module Ruling
      private

      def run_ruling_loop(intent)
        raw = nil
        contexts = intent[:affected_contexts]
        contexts = [intent[:primary_context]] if contexts.empty? && intent[:primary_context].present?
        raise AiError, "Ruling step reached with no affected contexts and no primary context — Intent step failed to classify" if contexts.empty?

        primary = intent[:primary_context]
        if primary && contexts.include?(primary)
          contexts = [primary] + (contexts - [primary])
        end

        previous_summaries = []
        rulings = []

        contexts.each_with_index do |domain, idx|
          prompt_summary = "Ruling [#{domain}] iteration #{idx + 1}/#{contexts.size}: " \
                           "\"#{@log.truncate(intent[:intention])}\""

          rules_text = Rules.fetch(*intent[:rules_needed])
          char_block = CharacterBlock.for(@sheet, category: domain)
          micro_ctx  = @adventure.send("#{domain}_context")
          creature_stats = CharacterBlock.creature_stats_for(@adventure)

          domain_instructions = PromptRenderer.render_partial("ruling/_#{domain}")

          system_prompt = PromptRenderer.render("ruling",
            domain: domain,
            character_block: char_block,
            micro_context: micro_ctx.present? ? micro_ctx.to_json : nil,
            creature_stats: creature_stats,
            previous_summaries: previous_summaries,
            rules_text: rules_text,
            domain_instructions: domain_instructions)

          request_body = { system_prompt: system_prompt, user_message: intent[:intention] }
          raw = @ai.chat(system_prompt: system_prompt, user_message: intent[:intention],
                          max_tokens: @config.token_budget_for("ruling"), step_name: "ruling",
                          model: @config.model_for("ruling"))
          parsed = @ai.parse_json(raw)
          @log.ai_log!("ruling", prompt_summary, raw, parsed,
                       parse_status: @ai.last_parse_status, request_body: request_body,
                       model_used: @ai.last_model_used)

          ruling = {
            domain: domain,
            player_rolls: Array(parsed["player_rolls"]).map(&:deep_symbolize_keys),
            npc_actions: Array(parsed["npc_actions"]).map(&:deep_symbolize_keys),
            consequences: Array(parsed["consequences"]).map(&:deep_symbolize_keys),
            ruling_summary: parsed["ruling_summary"] || ""
          }

          previous_summaries << "[#{domain.upcase}] #{ruling[:ruling_summary]}"
          rulings << ruling
        end

        rulings
      rescue TokenBudgetExceededError => e
        @log.ai_log_error!("ruling", "Ruling loop failed", e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           status: "token_budget_exceeded",
                           model_used: @ai.last_model_used)
        raise
      rescue AiError => e
        @log.ai_log_error!("ruling", "Ruling loop failed", e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           model_used: @ai.last_model_used)
        raise
      end

      def merge_rulings(rulings)
        {
          player_rolls: rulings.flat_map { |r| r[:player_rolls] },
          npc_actions: rulings.flat_map { |r| r[:npc_actions] },
          consequences: rulings.flat_map { |r| r[:consequences] },
          ruling_summaries: rulings.map { |r| "[#{r[:domain].upcase}] #{r[:ruling_summary]}" }
        }
      end
    end
  end
end
