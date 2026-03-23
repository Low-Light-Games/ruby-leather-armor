# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step: Unified Evaluation — single-call beacon + mecheval + rollqualifier.
    #
    # Replaces the 6 parallel beacons + N sequential mechanical evaluations + N roll
    # qualifiers with one AI call. Targets top-end models (o3, Claude 4, gpt-5) that
    # can handle cross-domain reasoning in a single pass with better coherence and
    # zero duplication.
    #
    # Activated by DmConfig `evaluation_mode: "unified"`. Returns the same two-value
    # contract as the standard path: (intent, evaluations).
    module UnifiedEvaluation
      private

      def run_unified_evaluation(intention)
        prompt_summary = "UnifiedEval: \"#{@log.truncate(intention)}\""

        char_block      = CharacterBlock.full(@sheet)
        micro_contexts  = PromptHelpers.build_micro_contexts_block(@adventure)
        creature_stats  = CharacterBlock.creature_stats_for(@adventure)
        rules_manifest  = build_unified_rules_manifest
        extra_context   = traversal_extra_context
        scene_summary   = @adventure.scene_summary

        domain_beacon_hints = build_all_beacon_hints
        domain_mecheval_hints = build_all_mecheval_hints

        response_schema = PromptRenderer.load_schema("unified_evaluation")

        system_prompt = PromptRenderer.render("unified_evaluation",
          character_block: char_block,
          micro_contexts: micro_contexts,
          creature_stats: creature_stats,
          rules_manifest: rules_manifest,
          extra_context: extra_context,
          scene_summary: scene_summary,
          domain_beacon_hints: domain_beacon_hints,
          domain_mecheval_hints: domain_mecheval_hints,
          response_schema: response_schema)

        request_body = { system_prompt: system_prompt, user_message: intention }

        parsed = timed_ai_call("unified_evaluation", prompt_summary, request_body) do
          raw = @ai.chat(
            system_prompt: system_prompt, user_message: intention,
            max_tokens: @config.token_budget_for("unified_evaluation"),
            step_name: "unified_evaluation",
            model: @config.model_for("unified_evaluation"))
          [raw, @ai.parse_json(raw)]
        end

        intent, evaluations = parse_unified_response(parsed, intention)
        evaluations = evaluations.map { |eval| compute_take_values(eval) }
        log_unified_to_loop(intent, evaluations)

        [intent, evaluations]
      end

      # -------------------------------------------------------------------
      # Response parsing — converts the unified JSON into the same contract
      # as converge_beacons + run_mechanical_evaluation_loop
      # -------------------------------------------------------------------

      def parse_unified_response(parsed, intention)
        domains = parsed["domains"] || {}

        beacon_results = {}
        affected_contexts = []
        needs_mechanics = false
        macro_significant = false
        rules_needed = []
        transition = nil
        destination = nil
        evaluations = []

        PromptHelpers::CONTEXT_FIELDS.each do |domain|
          d = (domains[domain] || {}).deep_symbolize_keys
          affected = d[:affected] == true

          beacon_results[domain] = {
            domain: domain,
            affected: affected,
            needs_mechanics: d[:needs_mechanics] == true,
            macro_significant: d[:macro_significant] == true,
            expand_scene: d[:expand_scene] == true,
            rules_needed: Array(d[:rules_needed]).map(&:to_s),
            domain_interpretation: d[:domain_interpretation],
            transition: d[:transition],
            destination: d[:destination],
            combatants: Array(d[:combatants])
          }

          next unless affected

          affected_contexts << domain
          needs_mechanics = true if d[:needs_mechanics] == true
          macro_significant = true if d[:macro_significant] == true
          rules_needed.concat(Array(d[:rules_needed]).map(&:to_s))
          transition ||= d[:transition]
          destination ||= d[:destination] if domain == "traversal"

          rolls = Array(d[:player_rolls]).map { |r| r.deep_symbolize_keys.merge(domain: domain) }
          npc_actions = Array(d[:npc_actions]).map(&:deep_symbolize_keys)
          consequences = Array(d[:consequences]).map(&:deep_symbolize_keys)
          summary = d[:mechanical_summary].to_s

          if rolls.any? || npc_actions.any? || consequences.any? || summary.present?
            evaluations << {
              domain: domain,
              player_rolls: rolls,
              npc_actions: npc_actions,
              consequences: consequences,
              mechanical_summary: summary,
              qualifier_context_hints: Array(d[:qualifier_context_hints])
            }
          end
        end

        primary_context = determine_primary(affected_contexts)
        plot_relevant = determine_plot_relevance(affected_contexts)
        expand_scene = beacon_results.dig("social", :expand_scene) == true

        intent = {
          intention: intention,
          needs_mechanics: needs_mechanics,
          expand_scene: expand_scene,
          destination: destination,
          affected_contexts: affected_contexts,
          primary_context: primary_context || "exploration",
          rules_needed: rules_needed.uniq,
          transition: transition,
          macro_significant: macro_significant,
          plot_relevant: plot_relevant,
          beacon_results: beacon_results
        }

        [intent, evaluations]
      end

      # -------------------------------------------------------------------
      # Roll qualification — sheet-math only
      # -------------------------------------------------------------------
      # The AI already provides take_10_eligible / take_20_eligible per roll.
      # This adds the numeric take_10_value / take_20_value from the character
      # sheet (skill modifier + 10 or + 20), which is deterministic and should
      # never come from the AI.

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

      # -------------------------------------------------------------------
      # Prompt-building helpers
      # -------------------------------------------------------------------

      def build_unified_rules_manifest
        manifest = Rules.manifest
        return nil if manifest.empty?

        PromptHelpers.format_manifest(manifest)
      end

      def build_all_beacon_hints
        PromptHelpers::CONTEXT_FIELDS.map do |domain|
          content = PromptRenderer.render_partial("beacon/_#{domain}")
          next if content.blank?
          "[#{domain.upcase}]\n#{content}"
        end.compact.join("\n\n")
      end

      def build_all_mecheval_hints
        PromptHelpers::CONTEXT_FIELDS.map do |domain|
          content = PromptRenderer.render_partial("mechanical_evaluation/_#{domain}")
          next if content.blank?
          "[#{domain.upcase}]\n#{content}"
        end.compact.join("\n\n")
      end

      # -------------------------------------------------------------------
      # AdventureLoop integration
      # -------------------------------------------------------------------

      def log_unified_to_loop(intent, evaluations)
        return unless @loop

        affected = intent[:affected_contexts]
        loop_tags = {}
        loop_tags["needs_mechanics"] = true if intent[:needs_mechanics]

        rolls_desc = evaluations.flat_map { |e| e[:player_rolls] }
                                .map { |r| "#{r[:skill] || r[:type]} DC #{r[:dc]} (#{r[:domain]})" }
                                .join(", ")

        loop_data = {
          "affected_contexts" => affected,
          "primary_context" => intent[:primary_context],
          "unified_eval" => true
        }

        @loop.batch_update!(
          new_tags: loop_tags.presence,
          new_data: loop_data,
          new_status: "resolving",
          timeline_entry: {
            "step" => "unified_eval",
            "summary" => "Affected: #{affected.join(', ').presence || 'none'}. Rolls: #{rolls_desc.presence || 'none'}",
            "at" => Time.current.iso8601
          })
        @loop.update_column(:category, intent[:primary_context]) if intent[:primary_context]
      end
    end
  end
end
