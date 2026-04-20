# frozen_string_literal: true

module DungeonMaster
  module Steps
    module Phases
      # Phase 2 of ParallelEvaluation — builds mechanical evaluation prompts,
      # calls the evaluator's /sequential endpoint, and parses results.
      module MechEvalPhase
        DOMAIN_PROMPT_RULES = {
          "inventory" => { creature_stats: false, npc_actions_guidance: false },
          "rest" => { creature_stats: false, npc_actions_guidance: false },
          "buff" => { creature_stats: false, npc_actions_guidance: false }
        }.freeze

        DOMAIN_ROLL_INVARIANTS = {
          "inventory" => {
            forbidden_types: %w[attack_roll damage_roll]
          },
          "exploration" => {
            forbidden_types: %w[attack_roll damage_roll]
          },
          "social" => {
            forbidden_types: %w[attack_roll damage_roll]
          },
          "rest" => {
            forbidden_types: %w[attack_roll damage_roll]
          },
          "buff" => {
            forbidden_types: %w[attack_roll damage_roll]
          },
          "traversal" => {
            forbidden_types: %w[attack_roll damage_roll],
            forbidden_skills: %w[Stealth]
          }
        }.freeze

        private

        def build_mech_eval_prompts(ordered_domains, intention, intent)
          prior = continuity_prior_outcomes
          ordered_domains.map do |domain|
            prompt_rules   = DOMAIN_PROMPT_RULES.fetch(domain.to_s, {})
            # buff: focused char block (spells + items only); context is active_buffs on the sheet;
            # no creature stats needed — buff eval produces no rolls and no NPC actions.
            char_block     = domain == "buff" ? CharacterBlock.buff(@sheet) : CharacterBlock.for(@sheet, category: domain)
            micro_ctx      = domain == "buff" ? @sheet&.active_buffs : @adventure.send("#{domain}_context")
            creature_stats = if prompt_rules[:creature_stats] == false || domain == "buff"
                               nil
                             else
                               CharacterBlock.creature_stats_for(@adventure)
                             end
            rules_text     = domain_rules_text_for(intent, domain)
            mech_eval_context = PromptViews::MechEvalPromptContext.new(
              domain: domain,
              character_block: char_block,
              micro_context: micro_ctx.present? ? micro_ctx.to_json : nil,
              creature_stats: creature_stats,
              rules_text: rules_text,
              prior_outcomes: prior,
              include_npc_actions_guidance: prompt_rules.fetch(:npc_actions_guidance, true)
            )

            system_prompt_base = case domain.to_s
            when "combat"
              attack_options = DungeonMaster::Combat::AttackOptionBuilder.call(
                sheet: @sheet,
                adventure: @adventure
              )
              combat_context = PromptViews::MechEvalPromptContext.new(
                domain: mech_eval_context.domain,
                character_block: mech_eval_context.character_block,
                micro_context: mech_eval_context.micro_context,
                creature_stats: mech_eval_context.creature_stats,
                rules_text: mech_eval_context.rules_text,
                prior_outcomes: mech_eval_context.prior_outcomes,
                attack_options_text: format_attack_options_for_prompt(attack_options),
                previous_summaries: []
              )
              PromptRenderer.render("combat_mechanic",
                mech_eval_context: combat_context)
            else
              instructions = PromptRenderer.render_partial("mechanical_evaluation/_#{domain}")
              mech_eval_context = PromptViews::MechEvalPromptContext.new(
                domain: mech_eval_context.domain,
                character_block: mech_eval_context.character_block,
                micro_context: mech_eval_context.micro_context,
                creature_stats: mech_eval_context.creature_stats,
                rules_text: mech_eval_context.rules_text,
                prior_outcomes: mech_eval_context.prior_outcomes,
                domain_instructions: instructions,
                include_npc_actions_guidance: mech_eval_context.include_npc_actions_guidance?
              )

              PromptRenderer.render("mechanical_evaluation",
                mech_eval_context: mech_eval_context)
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
              rolls = symbolize_hash_array(parsed[:player_rolls]).map { |r| r.merge(domain: domain) }
              [
                enforce_roll_domain_ownership(domain, rolls),
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

        def enforce_roll_domain_ownership(domain, rolls)
          rules = DOMAIN_ROLL_INVARIANTS[domain.to_s]
          return rolls unless rules

          Array(rolls).reject do |roll|
            violation = roll_domain_violation(rules, roll)
            next false unless violation

            @log&.play_log!(
              "ownership_guard",
              "Dropped #{domain} roll that violates domain ownership (#{violation})",
              parsed_response: {
                domain: domain,
                violation: violation,
                roll: roll
              }
            )
            true
          end
        end

        def roll_domain_violation(rules, roll)
          return "forbidden_type" if Array(rules[:forbidden_types]).include?(roll[:type].to_s)
          return "forbidden_skill" if Array(rules[:forbidden_skills]).include?(roll[:skill].to_s)

          nil
        end

        def format_attack_options_for_prompt(options)
          list = Array(options).map do |option|
            parts = [option[:id], option[:label]]
            if option[:damage].present?
              damage_label = [option[:damage], option[:damage_type]].compact.join(" ")
              parts << damage_label
            end
            "- #{parts.join(' | ')}"
          end

          list.presence&.join("\n") || "(no legal player attack options available)"
        end
      end
    end
  end
end
