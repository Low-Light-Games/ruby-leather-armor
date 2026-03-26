# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step: Parallel Evaluation — re-implements the beacon → mechanical
    # evaluation → roll qualifier chain via the Node evaluator microservice.
    #
    # Three HTTP phases, each a single POST to the evaluator:
    #   Phase 1 — POST /fan_out  : 6 beacon prompts run in parallel
    #   Phase 2 — POST /sequential : N mech_eval prompts run sequentially
    #   Phase 3 — POST /fan_out  : N roll_qualifier prompts run in parallel
    #
    # All prompts are rendered here in Rails (ERB templates). The Node service
    # is a stateless execution engine with no domain logic. Model and token
    # budgets are passed inline per request from DmConfig.
    #
    # Returns [intent, evaluations] — identical shape to run_unified_evaluation.
    module ParallelEvaluation
      DOMAINS = PromptHelpers::CONTEXT_FIELDS.freeze
      DOMAIN_PRIORITY = %w[combat social traversal exploration rest inventory].freeze

      private

      def run_parallel_evaluation(intention)
        broadcast_progress("Reading the situation...")
        evaluator_url = ENV.fetch("EVALUATOR_URL", "http://evaluator:3001")

        # ----------------------------------------------------------------
        # Phase 1 — Beacons (parallel)
        # ----------------------------------------------------------------
        beacon_prompts = build_beacon_prompts(intention)
        beacon_results = call_evaluator!(
          "#{evaluator_url}/fan_out", beacon_prompts, intention, phase: "beacons"
        )

        intent = converge_beacons(beacon_results, intention)
        log_parallel_to_loop(intent)

        # ----------------------------------------------------------------
        # Phase 2 — Mechanical Evaluation (sequential, affected domains only)
        # ----------------------------------------------------------------
        evaluations = []

        if intent[:needs_mechanics]
          affected = intent[:affected_contexts]
          ordered_domains = DOMAIN_PRIORITY.select { |d| affected.include?(d) } +
                            (affected - DOMAIN_PRIORITY)

          mech_prompts = build_mech_eval_prompts(ordered_domains, intention, intent)
          mech_results = call_evaluator!(
            "#{evaluator_url}/sequential", mech_prompts, intention, phase: "mech_eval"
          )

          evaluations = parse_mech_eval_results(mech_results, ordered_domains)

          # ----------------------------------------------------------------
          # Phase 3 — Roll Qualifier (parallel, domains with rolls only)
          # ----------------------------------------------------------------
          domains_with_rolls = evaluations.select { |e| e[:player_rolls].any? }

          if domains_with_rolls.any?
            qual_prompts = build_roll_qualifier_prompts(domains_with_rolls, intention)
            qual_results = call_evaluator!(
              "#{evaluator_url}/fan_out", qual_prompts, intention, phase: "roll_qualifier"
            )

            evaluations = apply_qualifier_results(evaluations, qual_results)
          end
        end

        evaluations = evaluations.map { |e| compute_take_values(e) }
        log_evaluations_to_loop(evaluations)

        [intent, evaluations]
      end

      # ----------------------------------------------------------------
      # HTTP transport — calls the Node evaluator, handles errors + logging
      # ----------------------------------------------------------------

      def call_evaluator!(url, prompts, intention, phase:)
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        uri      = URI(url)
        http     = Net::HTTP.new(uri.host, uri.port)
        http.read_timeout = 150
        http.open_timeout = 5

        request = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
        request.body = prompts.to_json

        response = http.request(request)
        duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round

        begin
          body = JSON.parse(response.body)
        rescue JSON::ParserError => e
          raise AiError, "Evaluator #{phase} returned non-JSON body (HTTP #{response.code}): #{e.message} — raw: #{response.body.truncate(500)}"
        end

        if response.code.to_i >= 400
          persist_partial_logs(Array(body.dig("partial_results")), intention)
          raise AiError, "Evaluator #{phase} failed (HTTP #{response.code}): #{body.dig("error") || response.body.truncate(500)}"
        end

        # Persist logs for all completed calls in this phase
        persist_node_logs(Array(body), intention)

        body
      rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, Net::ReadTimeout, Net::OpenTimeout => e
        raise AiError, "Evaluator unreachable during #{phase}: #{e.message}"
      end

      def persist_node_logs(results, intention)
        results.each do |result|
          meta = result["meta"] || {}
          step = meta["step"] || "unknown"
          domain = meta["domain"]
          summary = domain ? "#{step.titleize} [#{domain}]: \"#{@log.truncate(intention)}\"" : "#{step.titleize}: \"#{@log.truncate(intention)}\""

          usage_raw = result["usage"] || {}
          usage = {
            input_tokens:     usage_raw["input_tokens"].to_i,
            output_tokens:    usage_raw["output_tokens"].to_i,
            reasoning_tokens: usage_raw["reasoning_tokens"].to_i,
            total_tokens:     usage_raw["total_tokens"].to_i
          }

          @log.ai_log!(
            step,
            summary,
            result["raw_response"],
            result["parsed_response"],
            parse_status:  result["parse_status"] || "success",
            request_body:  result["request_body"],
            model_used:    result["model_used"],
            duration_ms:   result["duration_ms"],
            usage:         usage
          )
        end
      end

      def persist_partial_logs(partial_results, intention)
        persist_node_logs(partial_results, intention) if partial_results.any?
      end

      # ----------------------------------------------------------------
      # Phase 1 helpers — beacon prompts + convergence
      # ----------------------------------------------------------------

      def build_beacon_prompts(intention)
        DOMAINS.map do |domain|
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
            domain_instructions:  instructions)

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
          domain  = r.dig("meta", "domain")
          parsed  = (r["parsed_response"] || {}).deep_symbolize_keys
          h[domain] = parsed if domain
        end

        affected          = {}
        needs_mechanics   = false
        macro_significant = false
        transition        = nil
        destination       = nil
        expand_scene      = false
        domain_results    = {}

        DOMAINS.each do |domain|
          d = by_domain[domain] || {}
          is_affected = d[:affected] == true

          domain_results[domain] = {
            domain:              domain,
            affected:            is_affected,
            needs_mechanics:     d[:needs_mechanics] == true,
            macro_significant:   d[:macro_significant] == true,
            expand_scene:        domain == "social" && d[:expand_scene] == true,
            transition:          d[:transition],
            destination:         d[:destination],
            combatants:          Array(d[:combatants])
          }

          next unless is_affected

          affected[domain]  = true
          needs_mechanics   = true if d[:needs_mechanics] == true
          macro_significant = true if d[:macro_significant] == true
          transition      ||= d[:transition]
          destination     ||= d[:destination] if domain == "traversal"
        end

        expand_scene = domain_results.dig("social", :expand_scene) == true

        {
          intention:          intention,
          needs_mechanics:    needs_mechanics,
          expand_scene:       expand_scene,
          destination:        destination,
          affected_contexts:  affected.keys,
          transition:         transition,
          macro_significant:  macro_significant,
          domain_results:     domain_results
        }
      end

      # ----------------------------------------------------------------
      # Phase 2 helpers — mech_eval prompts + parsing
      # ----------------------------------------------------------------

      def build_mech_eval_prompts(ordered_domains, intention, intent)
        ordered_domains.map do |domain|
          char_block    = CharacterBlock.for(@sheet, category: domain)
          micro_ctx     = @adventure.send("#{domain}_context")
          creature_stats = CharacterBlock.creature_stats_for(@adventure)
          rules_text    = domain_rules_text_for(intent, domain)
          instructions  = PromptRenderer.render_partial("mechanical_evaluation/_#{domain}")

          # Render base prompt WITHOUT previous_summaries — Node injects those.
          system_prompt_base = PromptRenderer.render("mechanical_evaluation",
            domain:              domain,
            character_block:     char_block,
            micro_context:       micro_ctx.present? ? micro_ctx.to_json : nil,
            creature_stats:      creature_stats,
            previous_summaries:  [],
            rules_text:          rules_text,
            domain_instructions: instructions)

          {
            system_prompt_base:      system_prompt_base,
            user_message:            intention,
            model:                   @config.model_for("mechanical_evaluation"),
            max_tokens:              @config.token_budget_for("mechanical_evaluation"),
            summary_extraction_key:  "mechanical_summary",
            meta:                    { step: "mechanical_evaluation", domain: domain }
          }
        end
      end

      def parse_mech_eval_results(results, ordered_domains)
        results.each_with_index.filter_map do |result, idx|
          domain  = ordered_domains[idx] || result.dig("meta", "domain")
          parsed  = (result["parsed_response"] || {}).deep_symbolize_keys

          rolls        = Array(parsed[:player_rolls]).map { |r| r.deep_symbolize_keys.merge(domain: domain) }
          npc_actions  = Array(parsed[:npc_actions]).map(&:deep_symbolize_keys)
          consequences = Array(parsed[:consequences]).map(&:deep_symbolize_keys)
          summary      = parsed[:mechanical_summary].to_s

          next if rolls.empty? && npc_actions.empty? && consequences.empty? && summary.blank?

          {
            domain:              domain,
            player_rolls:        rolls,
            npc_actions:         npc_actions,
            consequences:        consequences,
            mechanical_summary:  summary
          }
        end
      end

      # ----------------------------------------------------------------
      # Phase 3 helpers — roll qualifier prompts + application
      # ----------------------------------------------------------------

      def build_roll_qualifier_prompts(evaluations_with_rolls, intention)
        evaluations_with_rolls.map do |eval|
          domain  = eval[:domain]
          context_block = build_qualifier_context_block(domain)

          system_prompt = PromptRenderer.render("roll_qualifier",
            domain:              domain,
            mechanical_summary:  eval[:mechanical_summary],
            rolls_json:          eval[:player_rolls].to_json,
            context_block:       context_block,
            scene_summary:       @adventure.scene_summary)

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

      # ----------------------------------------------------------------
      # Roll qualification — sheet-math only (mirrors UnifiedEvaluation)
      # ----------------------------------------------------------------

      def compute_take_values(evaluation)
        skills_lookup = build_skills_lookup

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

      # ----------------------------------------------------------------
      # Prompt-building helpers
      # ----------------------------------------------------------------

      def domain_rules_manifest(domain)
        manifest = Rules.manifest
        domain_entries = manifest.select { |e| e[:domain] == domain }
        return nil if domain_entries.empty?

        domain_entries.map do |e|
          line = "- #{e[:slug]}: #{e[:name]}"
          line += " — #{e[:brief]}" if e[:brief].present?
          line
        end.join("\n")
      end

      def domain_rules_text_for(intent, domain)
        # intent[:domain_results] holds rules_needed per domain when available
        domain_result = intent.dig(:domain_results, domain) || {}
        slugs = Array(domain_result[:rules_needed])
        slugs.any? ? Rules.fetch(*slugs) : nil
      end

      def build_traversal_extra_context_pe
        locs = @adventure.story.story_locations.includes(:connections_from, :connections_to)
        return nil if locs.empty?

        current = @adventure.current_location
        locs.map do |loc|
          marker = loc.id == current&.id ? " [CURRENT]" : ""
          marker += " [START]" if loc.starting
          conns = loc.connections.map do |c|
            other = c.other_location(loc)
            "#{other.name} (#{c.distance_miles} mi, #{c.terrain_type})"
          end
          "- #{loc.name}#{marker}: #{loc.description&.truncate(80) || '(no description)'}#{conns.any? ? "\n  Connects to: #{conns.join(', ')}" : ''}"
        end.join("\n")
      end

      def build_qualifier_context_block(domain)
        ctx = begin
          @adventure.send("#{domain}_context")
        rescue StandardError
          nil
        end
        ctx.present? ? "=== #{domain.upcase} CONTEXT ===\n#{ctx.to_json}" : nil
      end

      # ----------------------------------------------------------------
      # AdventureLoop integration
      # ----------------------------------------------------------------

      def log_parallel_to_loop(intent)
        return unless @loop

        affected = intent[:affected_contexts]
        loop_tags = {}
        loop_tags["needs_mechanics"] = true if intent[:needs_mechanics]

        @loop.batch_update!(
          new_tags: loop_tags.presence,
          new_data: { "affected_contexts" => affected, "parallel_eval" => true },
          new_status: "resolving",
          timeline_entry: {
            "step"    => "parallel_eval",
            "summary" => "Affected: #{affected.join(", ").presence || "none"}",
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
    end
  end
end
