# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Phase 2: InterpretationDispatchers — parallel per-domain interpretation.
    #
    # Given the pure intention from the Intent step, each dispatcher evaluates
    # how that intention affects a single game domain (combat, traversal, etc.).
    # Dispatchers run in parallel; results are merged by converge_dispatchers.
    module InterpretationDispatcher
      DOMAINS = PromptHelpers::CONTEXT_FIELDS.freeze # %w[traversal combat social exploration rest inventory]

      private

      # Run dispatchers for all domains (or filtered set) and merge results.
      def run_dispatchers(intention, category)
        domains = dispatcher_domains(category)
        results = {}

        threads = domains.map do |domain|
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              result = run_single_dispatcher(intention, domain)
              results[domain] = result
            end
          end
        end

        threads.each(&:value)
        converge_dispatchers(results, intention, category)
      end

      def run_single_dispatcher(intention, domain)
        raw = nil
        prompt_summary = "Dispatcher [#{domain}]: \"#{@log.truncate(intention)}\""

        char_data = CharacterBlock.for(@sheet, category: domain)
        domain_context = @adventure.send("#{domain}_context")
        rules_manifest = domain_rules_manifest(domain)
        domain_instructions = PromptRenderer.render_partial("dispatcher/_#{domain}")
        extra_context = domain == "traversal" ? traversal_extra_context : nil

        system_prompt = PromptRenderer.render("interpretation_dispatcher",
          domain: domain,
          character_data: char_data,
          domain_context: domain_context,
          rules_manifest: rules_manifest,
          extra_context: extra_context,
          domain_instructions: domain_instructions)

        request_body = { system_prompt: system_prompt, user_message: intention }
        raw = @ai.chat(system_prompt: system_prompt, user_message: intention,
                        max_tokens: @config.token_budget_for("dispatcher"), step_name: "dispatcher",
                        model: @config.model_for("dispatcher"))
        parsed = @ai.parse_json(raw)
        @log.ai_log!("dispatcher", prompt_summary, raw, parsed,
                     parse_status: @ai.last_parse_status, request_body: request_body,
                     model_used: @ai.last_model_used)

        {
          domain: domain,
          affected: parsed["affected"] == true,
          needs_mechanics: parsed["needs_mechanics"] == true,
          macro_significant: parsed["macro_significant"] == true,
          rules_needed: Array(parsed["rules_needed"]).map(&:to_s),
          domain_interpretation: parsed["domain_interpretation"],
          transition: parsed["transition"],
          destination: parsed["destination"]
        }
      rescue TokenBudgetExceededError => e
        @log.ai_log_error!("dispatcher", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, status: "token_budget_exceeded",
                           model_used: @ai.last_model_used)
        { domain: domain, affected: false, needs_mechanics: false, macro_significant: false,
          rules_needed: [], domain_interpretation: "Error: #{e.message}", transition: nil, destination: nil }
      rescue AiError => e
        @log.ai_log_error!("dispatcher", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, model_used: @ai.last_model_used)
        { domain: domain, affected: false, needs_mechanics: false, macro_significant: false,
          rules_needed: [], domain_interpretation: "Error: #{e.message}", transition: nil, destination: nil }
      end

      # Merge parallel dispatcher results into a unified intent-compatible hash.
      def converge_dispatchers(results, intention, category)
        affected = results.select { |_, r| r[:affected] }
        needs_mechanics = affected.any? { |_, r| r[:needs_mechanics] }
        macro_significant = results.any? { |_, r| r[:macro_significant] }
        rules_needed = affected.flat_map { |_, r| r[:rules_needed] }.uniq
        transition = affected.filter_map { |_, r| r[:transition] }.first

        affected_contexts = affected.keys
        primary_context = affected_contexts.include?(category) ? category : affected_contexts.first

        destination = results.dig("traversal", :destination)

        plot_relevant = determine_plot_relevance(primary_context)

        {
          intention: intention,
          needs_mechanics: needs_mechanics,
          destination: destination,
          affected_contexts: affected_contexts,
          primary_context: primary_context || category,
          rules_needed: rules_needed,
          transition: transition,
          macro_significant: macro_significant,
          plot_relevant: plot_relevant,
          dispatcher_results: results
        }
      end

      # Determine which domains to dispatch to based on config.
      def dispatcher_domains(category)
        scope = @config.get("interpreter_scope") || "all"

        if scope == "filtered"
          domains = [category].compact & DOMAINS
          active = DOMAINS.select { |d| @adventure.send("#{d}_context").present? }
          (domains + active).uniq
        else
          DOMAINS.dup
        end
      end

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

      def traversal_extra_context
        locs = @adventure.story.story_locations.includes(:connections_from, :connections_to)
        return nil if locs.empty?

        current = @adventure.current_location
        lines = locs.map do |loc|
          marker = loc.id == current&.id ? " [CURRENT]" : ""
          marker += " [START]" if loc.starting
          conns = loc.connections.map do |c|
            other = c.other_location(loc)
            "#{other.name} (#{c.distance_miles} mi, #{c.terrain_type})"
          end
          "- #{loc.name}#{marker}: #{loc.description&.truncate(80) || '(no description)'}#{conns.any? ? "\n  Connects to: #{conns.join(', ')}" : ''}"
        end

        "=== STORY LOCATIONS ===\n#{lines.join("\n")}"
      end

      def determine_plot_relevance(primary_context)
        story = @adventure.story
        npcs = StoryNpc.where(story_id: story.id).where(secret: false)
        clues = StoryClue.where(story_id: story.id)
        discovered = (@adventure.plot_state || {})["discovered_clues"] || []
        undiscovered = clues.reject { |c| discovered.include?(c.id) }

        return false if npcs.empty? && undiscovered.empty?

        current_loc_id = @adventure.current_location_id
        loc_has_clues = undiscovered.any? { |c| c.location_id.nil? || c.location_id == current_loc_id }
        method_match = undiscovered.any? do |c|
          Pipeline::METHOD_CONTEXT_MAP[c.discovery_method] == primary_context
        end

        loc_has_clues || method_match || npcs.any?
      end
    end
  end
end
