# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step: Parallel Evaluation — orchestrates the beacon →
    # mechanical evaluation → roll qualifier chain via the Node evaluator
    # microservice.
    #
    # Three HTTP phases, each a POST to the evaluator:
    #   Phase 1 — POST /fan_out    : 6 beacon prompts run in parallel
    #   Phase 2 — POST /sequential : N mech_eval prompts run sequentially
    #   Phase 3 — POST /fan_out    : N roll_qualifier prompts run in parallel
    #
    # Prompt building and result parsing for each phase live in dedicated
    # sub-modules:
    #   Phases::BeaconPhase        — phase 1 prompt building + convergence
    #   Phases::MechEvalPhase      — phase 2 prompt building + parsing
    #   Phases::RollQualifierPhase — phase 3 prompt building + qualifier merge
    #
    # HTTP transport is handled by EvaluatorTransport (already included by
    # PipelineEngine). Returns [intent, evaluations] — identical shape to
    # run_unified_evaluation.
    module ParallelEvaluation
      include Phases::BeaconPhase
      include Phases::MechEvalPhase
      include Phases::RollQualifierPhase

      # CONTEXT_FIELDS drives micro-context columns on Adventure (traversal_context, etc.).
      # DOMAINS adds "buff" which has no adventure column — its context is sheet.active_buffs.
      DOMAINS        = (PromptHelpers::CONTEXT_FIELDS + %w[buff]).freeze
      DOMAIN_PRIORITY = %w[combat buff social traversal exploration rest inventory].freeze

      private

      def run_parallel_evaluation(intention)
        broadcast_progress("Reading the situation...")

        # Phase 1 — Beacons (raw array; converge_beacons reads result order, not step keys)
        beacon_results = call_evaluator!(
          "#{evaluator_base_url}/fan_out",
          build_beacon_prompts(intention),
          intention,
          phase: "beacons"
        )

        intent = converge_beacons(beacon_results, intention)
        intent = prepare_canonical_combatants(intent)
        log_parallel_to_loop(intent)

        # Phase 2 — Mechanical Evaluation
        evaluations = []

        if intent[:affected_contexts].any?
          affected       = intent[:affected_contexts]
          ordered_domains = DOMAIN_PRIORITY.select { |d| affected.include?(d) } +
                            (affected - DOMAIN_PRIORITY)

          mech_results = evaluator_sequential!(
            build_mech_eval_prompts(ordered_domains, intention, intent),
            intention,
            phase: "mech_eval"
          )

          evaluations = parse_mech_eval_results(mech_results, ordered_domains)

          # Phase 3 — Roll Qualifier (raw array; apply_qualifier_results reads result order)
          domains_with_rolls = evaluations.select { |e| e[:player_rolls].any? }

          if domains_with_rolls.any?
            qual_results = call_evaluator!(
              "#{evaluator_base_url}/fan_out",
              build_roll_qualifier_prompts(domains_with_rolls, intention),
              intention,
              phase: "roll_qualifier"
            )

            evaluations = apply_qualifier_results(evaluations, qual_results)
          end
        end

        evaluations = evaluations.map { |e| compute_take_values(e) }
        log_evaluations_to_loop(evaluations)

        [intent, evaluations]
      end

      # ── Shared prompt helpers ──────────────────────────────────────

      def domain_rules_manifest(domain)
        manifest      = Rules.manifest
        domain_entries = manifest.select { |e| e[:domain] == domain }
        return nil if domain_entries.empty?

        domain_entries.map do |e|
          line = "- #{e[:slug]}: #{e[:name]}"
          line += " — #{e[:brief]}" if e[:brief].present?
          line
        end.join("\n")
      end

      def domain_rules_text_for(intent, domain)
        domain_result = intent.dig(:domain_results, domain) || {}
        slugs         = Array(domain_result[:rules_needed])
        slugs.any? ? Rules.fetch(*slugs) : nil
      end

      def build_traversal_extra_context_pe
        locs    = @adventure.story.story_locations.includes(:connections_from, :connections_to)
        current = @adventure.current_location
        return nil if locs.empty?

        locs.map do |loc|
          marker = loc.id == current&.id ? " [CURRENT]" : ""
          marker += " [START]" if loc.starting
          conns  = loc.connections.map do |c|
            other = c.other_location(loc)
            "#{other.name} (#{c.distance_miles} mi, #{c.terrain_type})"
          end
          "- #{loc.name}#{marker}: #{loc.description&.truncate(80) || '(no description)'}#{conns.any? ? "\n  Connects to: #{conns.join(', ')}" : ''}"
        end.join("\n")
      end

      def build_qualifier_context_block(domain)
        # buff always returns empty player_rolls so qualifier never runs for it;
        # also, there is no adventure.buff_context column — be explicit rather than
        # relying on the rescue nil fallback.
        return nil if domain == "buff"

        ctx = @adventure.send("#{domain}_context") rescue nil
        ctx.present? ? "=== #{domain.upcase} CONTEXT ===\n#{ctx.to_json}" : nil
      end

      def prepare_canonical_combatants(intent)
        return intent if @adventure.combat_active?

        combat_result = intent.dig(:domain_results, "combat") || {}
        transition = combat_result[:transition].to_s
        return intent unless DungeonMaster::CombatTransitions.start?(transition)

        combatant_names = Array(combat_result[:combatants]).map(&:to_s).reject(&:blank?)
        return intent if combatant_names.empty?

        prepared = Utilities::Warmaster.prepare_from_names!(
          names_preparation_request: Utilities::Warmaster::NamesPreparationRequest.new(
            adventure: @adventure,
            combatant_names: combatant_names,
            sheet: @sheet,
            log: @log,
            config: @config,
            ai: @ai
          )
        )

        return intent if prepared[:status] == :no_creatures

        Utilities::Warmaster.persist_pending_combat!(
          adventure: @adventure,
          creature_data: prepared[:creature_data]
        )

        @log.play_log!(
          "warmaster",
          "Pending combat roster prepared: #{prepared[:creature_data].size} creature(s)",
          parsed_response: {
            pending_combat: true,
            creature_count: prepared[:creature_data].size,
            creatures: prepared[:creature_data].map do |creature|
              {
                name: creature[:name],
                creature_sheet_id: creature[:creature_sheet_id],
                initiative: creature[:initiative]
              }
            end
          }
        )

        intent.merge(creature_data: prepared[:creature_data])
      end

      # ── AdventureLoop integration ──────────────────────────────────

      def log_parallel_to_loop(intent)
        return unless @loop

        affected   = intent[:affected_contexts]
        @loop.batch_update!(
          new_data:  { "affected_contexts" => affected, "parallel_eval" => true },
          new_status: "resolving",
          timeline_entry: {
            "step"    => "parallel_eval",
            "summary" => "Affected: #{affected.join(', ').presence || 'none'}",
            "at"      => Time.current.iso8601
          })
      end

      def log_evaluations_to_loop(evaluations)
        return unless @loop

        rolls_desc = evaluations.flat_map { |e| e[:player_rolls] }
                                .map { |r| "#{r[:skill] || r[:type]} DC #{r[:dc]} (#{r[:domain]})" }
                                .join(", ")

        @loop.batch_update!(
          timeline_entry: {
            "step"    => "mech_eval",
            "summary" => rolls_desc.presence || "No rolls",
            "at"      => Time.current.iso8601
          })
      end

      def continuity_prior_outcomes
        return [] unless action_queue_continuity? && @loop && @log&.registry_entry_uuid

        AdventureLoop.prior_pipeline_outcomes_before(
          registry_entry_uuid: @log.registry_entry_uuid,
          current_loop: @loop)
      end
    end
  end
end
