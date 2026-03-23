# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step: Beacon — parallel per-domain interpretation.
    #
    # Given the sanitized player input, each domain beacon evaluates how
    # that intention affects a single game domain
    # (combat, traversal, etc.). Beacons run in parallel; results are merged
    # by converge_beacons.
    module Beacon
      DOMAINS = PromptHelpers::CONTEXT_FIELDS.freeze # %w[traversal combat social exploration rest inventory]

      private

      DOMAIN_PRIORITY = %w[combat social traversal exploration rest inventory].freeze

      DISCOVERY_METHOD_CONTEXT_MAP = {
        "social" => "social", "exploration" => "exploration",
        "magic" => "exploration", "combat" => "combat", "automatic" => nil,
      }.freeze

      # Run beacons for all domains and merge results.
      def run_beacon(intention)
        domains = DOMAINS.dup
        results = {}

        threads = domains.map do |domain|
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              result = run_single_beacon(intention, domain)
              results[domain] = result
            end
          end
        end

        threads.each(&:value)
        converged = converge_beacons(results, intention)

        if @loop
          affected = converged[:affected_contexts]
          loop_tags = {}
          loop_tags["needs_mechanics"] = true if converged[:needs_mechanics]
          loop_data = { "affected_contexts" => affected, "primary_context" => converged[:primary_context] }
          @loop.batch_update!(
            new_tags: loop_tags.presence,
            new_data: loop_data,
            new_status: "resolving",
            timeline_entry: { "step" => "beacon", "summary" => "Affected: #{affected.join(', ').presence || 'none'}", "at" => Time.current.iso8601 })
          @loop.update_column(:category, converged[:primary_context]) if converged[:primary_context]
        end

        converged
      end

      def run_single_beacon(intention, domain)
        prompt_summary = "Beacon [#{domain}]: \"#{@log.truncate(intention)}\""

        char_data = CharacterBlock.for(@sheet, category: domain)
        domain_context = @adventure.send("#{domain}_context")
        rules_manifest = domain_rules_manifest(domain)
        domain_instructions = PromptRenderer.render_partial("beacon/_#{domain}")
        extra_context = domain == "traversal" ? traversal_extra_context : nil

        system_prompt = PromptRenderer.render("beacon",
          domain: domain,
          character_data: char_data,
          domain_context: domain_context,
          rules_manifest: rules_manifest,
          extra_context: extra_context,
          domain_instructions: domain_instructions)

        request_body = { system_prompt: system_prompt, user_message: intention }

        parsed = timed_ai_call("beacon", prompt_summary, request_body) do
          raw = @ai.chat(system_prompt: system_prompt, user_message: intention,
                          max_tokens: @config.token_budget_for("beacon"), step_name: "beacon",
                          model: @config.model_for("beacon"))
          [raw, @ai.parse_json(raw)]
        end

        {
          domain: domain,
          affected: parsed["affected"] == true,
          needs_mechanics: parsed["needs_mechanics"] == true,
          macro_significant: parsed["macro_significant"] == true,
          expand_scene: parsed["expand_scene"] == true,
          rules_needed: Array(parsed["rules_needed"]).map(&:to_s),
          domain_interpretation: parsed["domain_interpretation"],
          transition: parsed["transition"],
          destination: parsed["destination"],
          combatants: Array(parsed["combatants"])
        }
      rescue TokenBudgetExceededError, AiError => e
        pipeline_error!("beacon_#{domain}", e)
      end

      # Merge parallel beacon results into a unified intent-compatible hash.
      def converge_beacons(results, intention)
        affected = results.select { |_, r| r[:affected] }
        needs_mechanics = affected.any? { |_, r| r[:needs_mechanics] }
        macro_significant = results.any? { |_, r| r[:macro_significant] }
        rules_needed = affected.flat_map { |_, r| r[:rules_needed] }.uniq
        transition = affected.filter_map { |_, r| r[:transition] }.first

        affected_contexts = affected.keys
        primary_context = determine_primary(affected_contexts)

        destination = results.dig("traversal", :destination)

        plot_relevant = determine_plot_relevance(affected_contexts)

        expand_scene = results.dig("social", :expand_scene) == true

        {
          intention: intention,
          needs_mechanics: needs_mechanics,
          expand_scene: expand_scene,
          destination: destination,
          affected_contexts: affected_contexts,
          primary_context: primary_context || "exploration",
          rules_needed: rules_needed,
          transition: transition,
          macro_significant: macro_significant,
          plot_relevant: plot_relevant,
          beacon_results: results
        }
      end

      def determine_primary(affected_contexts)
        DOMAIN_PRIORITY.find { |d| affected_contexts.include?(d) } || affected_contexts.first
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

        lines.join("\n")
      end

      def determine_plot_relevance(affected_contexts)
        story = @adventure.story
        npcs = StoryNpc.where(story_id: story.id).where(secret: false)
        clues = StoryClue.where(story_id: story.id)
        discovered = (@adventure.plot_state || {})["discovered_clues"] || []
        undiscovered = clues.reject { |c| discovered.include?(c.id) }

        return false if npcs.empty? && undiscovered.empty?

        current_loc_id = @adventure.current_location_id
        loc_has_clues = undiscovered.any? { |c| c.location_id.nil? || c.location_id == current_loc_id }
        ctx_set = Array(affected_contexts)
        method_match = undiscovered.any? do |c|
          expected = DISCOVERY_METHOD_CONTEXT_MAP[c.discovery_method]
          expected.nil? || ctx_set.include?(expected)
        end

        loc_has_clues || method_match || npcs.any?
      end
    end
  end
end
