# frozen_string_literal: true

module DungeonMaster
  module Steps
    module Phases
      # Phase 3 of ParallelEvaluation — builds roll qualifier prompts,
      # calls the evaluator's /fan_out endpoint, merges qualifications
      # back onto evaluations, and computes take-10/take-20 values.
      module RollQualifierPhase
        private

        def build_roll_qualifier_prompts(evaluations_with_rolls, intention)
          evaluations_with_rolls.map do |eval|
            domain        = eval[:domain]
            context_block = build_qualifier_context_block(domain)

            system_prompt = PromptRenderer.render("roll_qualifier",
              domain:             domain,
              mechanical_summary: eval[:mechanical_summary],
              rolls_json:         eval[:player_rolls].to_json,
              context_block:      context_block,
              scene_summary:      @adventure.scene_summary)

            {
              system_prompt: system_prompt,
              user_message:  intention,
              model:         @config.model_for("roll_qualifier"),
              max_tokens:    @config.token_budget_for("roll_qualifier"),
              meta:          { step: "roll_qualifier", domain: domain }
            }
          end
        end

        def apply_qualifier_results(evaluations, qual_results)
          qual_by_domain = qual_results.each_with_object({}) do |r, h|
            domain = r.dig("meta", "domain")
            h[domain] = (r["parsed_response"] || {}).deep_symbolize_keys if domain
          end

          evaluations.map do |eval|
            qual = qual_by_domain[eval[:domain]]
            next eval unless qual

            qualifications = Array(qual[:qualifications])
            qual_by_skill  = qualifications.index_by { |q| q[:skill].to_s }

            qualified_rolls = eval[:player_rolls].map do |roll|
              q    = qual_by_skill[roll[:skill].to_s]
              base = roll.dup

              if q
                base[:take_10_eligible]      = q[:take_10_eligible] == true
                base[:take_20_eligible]      = q[:take_20_eligible] == true
                base[:situational_modifiers] = Array(q[:situational_modifiers]).map(&:deep_symbolize_keys)
              end

              base
            end

            eval.merge(player_rolls: qualified_rolls)
          end
        end

        def compute_take_values(evaluation)
          skills_lookup = Rolls::PlayerRolls.skills_lookup_from_sheet(@sheet)

          qualified_rolls = evaluation[:player_rolls].map do |roll|
            base = roll.dup
            if roll[:type].to_s == "skill_check" && roll[:skill].present?
              mod = skills_lookup[roll[:skill].to_s].to_i
              base[:take_10_value] = 10 + mod
              base[:take_20_value] = 20 + mod
            end
            base
          end

          evaluation.merge(player_rolls: qualified_rolls)
        end
      end
    end
  end
end
