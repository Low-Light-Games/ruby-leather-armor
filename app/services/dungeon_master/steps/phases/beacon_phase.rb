# frozen_string_literal: true

module DungeonMaster
  module Steps
    module Phases
      # Phase 1 of ParallelEvaluation — builds beacon prompts, calls
      # the evaluator's /fan_out endpoint, and converges results into
      # a single intent hash.
      module BeaconPhase
        private

        def build_beacon_prompts(intention)
          prior = continuity_prior_outcomes
          ParallelEvaluation::DOMAINS.map do |domain|
            char_data    = CharacterBlock.for(@sheet, category: domain)
            domain_ctx   = @adventure.send("#{domain}_context")
            rules_mfst   = domain_rules_manifest(domain)
            extra_ctx    = domain == "traversal" ? build_traversal_extra_context_pe : nil
            instructions = PromptRenderer.render_partial("beacon/_#{domain}",
                             domain_context: domain_ctx)

            system_prompt = PromptRenderer.render("beacon",
              domain:               domain,
              character_data:       char_data,
              domain_context:       domain_ctx,
              rules_manifest:       rules_mfst,
              extra_context:        extra_ctx,
              domain_instructions:  instructions,
              prior_outcomes:       prior)

            {
              system_prompt: system_prompt,
              user_message:  intention,
              model:         @config.model_for("beacon"),
              max_tokens:    @config.token_budget_for("beacon"),
              meta:          { step: "beacon", domain: domain }
            }
          end
        end

        def converge_beacons(results, intention)
          by_domain = results.each_with_object({}) do |r, h|
            domain = r.dig("meta", "domain")
            parsed = (r["parsed_response"] || {}).deep_symbolize_keys
            h[domain] = parsed if domain
          end

          affected          = {}
          needs_mechanics   = false
          macro_significant = false
          transition        = nil
          destination       = nil
          domain_results    = {}

          ParallelEvaluation::DOMAINS.each do |domain|
            d          = by_domain[domain] || {}
            is_affected = d[:affected] == true

            domain_results[domain] = {
              domain:            domain,
              affected:          is_affected,
              needs_mechanics:   d[:needs_mechanics] == true,
              macro_significant: d[:macro_significant] == true,
              expand_scene:      domain == "social" && d[:expand_scene] == true,
              transition:        d[:transition],
              destination:       d[:destination],
              combatants:        Array(d[:combatants])
            }

            next unless is_affected

            affected[domain]   = true
            needs_mechanics    = true if d[:needs_mechanics] == true
            macro_significant  = true if d[:macro_significant] == true
            transition       ||= d[:transition]
            destination      ||= d[:destination] if domain == "traversal"
          end

          expand_scene = domain_results.dig("social", :expand_scene) == true

          combat_ending = ParallelEvaluation::DOMAINS.any? do |domain|
            by_domain[domain]&.dig(:transition).to_s == "combat_ended"
          end

          {
            intention:         intention,
            needs_mechanics:   needs_mechanics,
            expand_scene:      expand_scene,
            destination:       destination,
            affected_contexts: affected.keys,
            transition:        transition,
            macro_significant: macro_significant,
            combat_ending:     combat_ending,
            domain_results:    domain_results
          }
        end
      end
    end
  end
end
