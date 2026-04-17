# frozen_string_literal: true

module DungeonMaster
  module Steps
    module Phases
      # Phase 2 of ParallelEvaluation — builds mechanical evaluation prompts,
      # calls the evaluator's /sequential endpoint, and parses results.
      module MechEvalPhase
        private

        def build_mech_eval_prompts(ordered_domains, intention, intent)
          prior = continuity_prior_outcomes
          ordered_domains.map do |domain|
            # buff: focused char block (spells + items only); context is active_buffs on the sheet;
            # no creature stats needed — buff eval produces no rolls and no NPC actions.
            char_block     = domain == "buff" ? CharacterBlock.buff(@sheet) : CharacterBlock.for(@sheet, category: domain)
            micro_ctx      = domain == "buff" ? @sheet&.active_buffs : @adventure.send("#{domain}_context")
            creature_stats = domain == "buff" ? nil : CharacterBlock.creature_stats_for(@adventure)
            rules_text     = domain_rules_text_for(intent, domain)

            system_prompt_base = case domain.to_s
            when "combat"
              PromptRenderer.render("combat_mechanic",
                domain:              domain,
                character_block:     char_block,
                micro_context:       micro_ctx.present? ? micro_ctx.to_json : nil,
                creature_stats:      creature_stats,
                previous_summaries:  [],
                rules_text:          rules_text,
                prior_outcomes:      prior)
            else
              instructions = PromptRenderer.render_partial("mechanical_evaluation/_#{domain}")

              PromptRenderer.render("mechanical_evaluation",
                domain:              domain,
                character_block:     char_block,
                micro_context:       micro_ctx.present? ? micro_ctx.to_json : nil,
                creature_stats:      creature_stats,
                previous_summaries:  [],
                rules_text:          rules_text,
                domain_instructions: instructions,
                prior_outcomes:      prior)
            end

            {
              system_prompt_base:     system_prompt_base,
              user_message:           intention,
              model:                  @config.model_for("mechanical_evaluation"),
              max_tokens:             @config.token_budget_for("mechanical_evaluation"),
              summary_extraction_key: "mechanical_summary",
              meta:                   { step: "mechanical_evaluation", domain: domain }
            }
          end
        end

        def parse_mech_eval_results(results, ordered_domains)
          results.each_with_index.filter_map do |result, idx|
            domain = ordered_domains[idx] || result.dig("meta", "domain")
            parsed = (result["parsed_response"] || {}).deep_symbolize_keys

            rolls, npc_actions, consequences, summary = case domain.to_s
            when "combat"
              begin
                merged = CombatMechanicResolution.call(
                  parsed: parsed,
                  domain: domain,
                  adventure: @adventure,
                  sheet: @sheet,
                  log: @log
                )
                [
                  merged[:player_rolls],
                  merged[:npc_actions],
                  merged[:consequences],
                  merged[:mechanical_summary].to_s
                ]
              rescue DungeonMaster::CombatMechanicResolutionError => e
                @log&.play_log!("combat_mech_eval_resolution_error", e.message)
                raise DungeonMaster::AiError,
                      "Combat mechanical evaluation could not resolve rolls (#{e.code}): #{e.message}"
              end
            else
              [
                symbolize_hash_array(parsed[:player_rolls]).map { |r| r.merge(domain: domain) },
                symbolize_hash_array(parsed[:npc_actions]),
                symbolize_hash_array(parsed[:consequences]),
                parsed[:mechanical_summary].to_s
              ]
            end

            next if rolls.empty? && npc_actions.empty? && consequences.empty? && summary.blank?

            {
              domain:             domain,
              player_rolls:       rolls,
              npc_actions:        npc_actions,
              consequences:       consequences,
              mechanical_summary: summary
            }
          end
        end

        def symbolize_hash_array(value)
          Array(value).filter_map do |entry|
            next unless entry.is_a?(Hash)

            entry.deep_symbolize_keys
          end
        end
      end
    end
  end
end
