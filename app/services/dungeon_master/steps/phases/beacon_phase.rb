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
          prior            = continuity_prior_outcomes
          @beacon_combat_live = @adventure.combat_context&.dig("active") == true

          ParallelEvaluation::DOMAINS.filter_map do |domain|
            # During active combat: combat is injected deterministically in converge_beacons;
            # buff mutations are owned by CombatGM, not the buff beacon.
            next if @beacon_combat_live && domain.in?(%w[combat buff])

            domain_ctx = domain == "buff" ? @sheet&.active_buffs : @adventure.send("#{domain}_context")
            {
              system_prompt: beacon_system_prompt(domain, domain_ctx, prior),
              user_message:  intention,
              model:         @config.model_for("beacon"),
              max_tokens:    @config.token_budget_for("beacon"),
              meta:          { step: "beacon", domain: domain }
            }
          end
        end

        def beacon_system_prompt(domain, domain_ctx, prior)
          return PromptRenderer.render("combat_beacon",
            domain_context:  domain_ctx,
            recent_messages: recent_story_messages,
            prior_outcomes:  prior) if domain == "combat"

          return PromptRenderer.render("buff_beacon",
            domain_context: domain_ctx,
            prior_outcomes: prior) if domain == "buff"

          char_data    = CharacterBlock.for(@sheet, category: domain)
          rules_mfst   = domain_rules_manifest(domain)
          extra_ctx    = build_extra_context_for(domain)
          instructions = PromptRenderer.render_partial("beacon/_#{domain}", domain_context: domain_ctx)
          PromptRenderer.render("beacon",
            domain:              domain,
            character_data:      char_data,
            domain_context:      domain_ctx,
            rules_manifest:      rules_mfst,
            extra_context:       extra_ctx,
            domain_instructions: instructions,
            prior_outcomes:      prior)
        end

        def recent_story_messages
          @adventure.adventure_messages
                    .where(message_type: %w[narrative action_result])
                    .or(@adventure.adventure_messages.where(role: "player"))
                    .newest_first.limit(4).reverse
        end

        def build_extra_context_for(domain)
          return unless domain == "traversal"

          parts = [build_traversal_extra_context_pe]
          if @beacon_combat_live
            parts << "=== COMBAT STATE ===\n#{@adventure.combat_context.to_json}"
          end
          parts.compact.join("\n\n").presence
        end

        def converge_beacons(results, intention)
          by_domain = results.each_with_object({}) do |r, h|
            domain = r.dig("meta", "domain")
            parsed = (r["parsed_response"] || {}).deep_symbolize_keys
            h[domain] = parsed if domain
          end

          affected          = {}
          macro_significant = false
          transition        = nil
          destination       = nil
          domain_results    = {}

          ParallelEvaluation::DOMAINS.each do |domain|
            d          = by_domain[domain] || {}
            combat_now = domain == "combat" ? d[:combat_now] == true : false
            is_affected = domain == "combat" ? combat_now : d[:affected] == true
            combat_transition = combat_now ? "combat_started" : d[:transition]
            normalized_combatants = normalized_combatants(d[:combatants], d[:count])

            domain_results[domain] = {
              domain:            domain,
              affected:          is_affected,
              macro_significant: d[:macro_significant] == true,
              expand_scene:      domain == "social" && d[:expand_scene] == true,
              transition:        combat_transition,
              destination:       d[:destination],
              combatants:        normalized_combatants
            }

            log_single_creature_combat_manifest!(d, normalized_combatants) if domain == "combat" && combat_now

            next unless is_affected

            affected[domain]   = true
            macro_significant  = true if d[:macro_significant] == true
            transition       ||= combat_transition
            destination      ||= d[:destination] if domain == "traversal"
          end

          # During active combat the beacon was skipped — force routing deterministically.
          # Use the same snapshot read at beacon-build time to avoid a second DB/cache access.
          if @beacon_combat_live
            domain_results["combat"] = (domain_results["combat"] || {}).merge(
              domain:          "combat",
              affected:        true
            )
            affected["combat"] = true
          # Combat just starting: beacon named combatants but may have forgotten affected.
          elsif (cr = domain_results["combat"]) && !cr[:affected] &&
                Array(cr[:combatants]).any? &&
                DungeonMaster::CombatTransitions.start?(cr[:transition])
            domain_results["combat"] = cr.merge(affected: true)
            affected["combat"] = true
          end

          expand_scene = domain_results.dig("social", :expand_scene) == true

          combat_ending = ParallelEvaluation::DOMAINS.any? do |domain|
            by_domain[domain]&.dig(:transition).to_s == "combat_ended"
          end

          {
            intention:         intention,
            expand_scene:      expand_scene,
            destination:       destination,
            affected_contexts: affected.keys,
            transition:        transition,
            macro_significant: macro_significant,
            combat_ending:     combat_ending,
            domain_results:    domain_results
          }
        end

        def normalized_combatants(raw_combatants, raw_count)
          compact_entries = Array(raw_combatants).filter_map do |entry|
            case entry
            when Hash
              key, value = entry.to_a.first
              next if key.blank?

              count = value.to_i
              next if count <= 0

              [key.to_s.strip, count]
            else
              name = entry.to_s.strip
              next if name.blank?

              [name, 1]
            end
          end

          if compact_entries.empty?
            names = Array(raw_combatants).map { |entry| entry.to_s.strip }.reject(&:blank?)
            count = raw_count.to_i
            return names if names.empty?
            return names unless names.one? && count > 1

            return Array.new(count, names.first)
          end

          compact_entries.flat_map do |name, count|
            Array.new(count, name)
          end
        end

        def log_single_creature_combat_manifest!(raw_combat_domain, normalized_combatants)
          return unless normalized_combatants.size == 1

          raw_total = Array(raw_combat_domain[:combatants]).sum do |entry|
            entry.is_a?(Hash) ? entry.values.first.to_i : 1
          end
          return unless raw_total == 1

          @log&.play_log!(
            "combat_beacon_single_manifest",
            "Combat beacon started combat with a single-creature manifest; preserving as-is.",
            parsed_response: {
              combatants: raw_combat_domain[:combatants],
              count: raw_combat_domain[:count]
            }
          )
        end
      end
    end
  end
end
