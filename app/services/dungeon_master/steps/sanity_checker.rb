# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step: SanityChecker.
    #
    # Two sub-checks under one umbrella:
    #
    #   A) Capability Check — validates that the player possesses the spells,
    #      feats, items, or class abilities they intend to *use*. Runs in parallel
    #      with MechanicalEvaluation inside the full affected-domain gate.
    #      Split responsibility: the AI extracts *what* is being used (NLP problem),
    #      Ruby verifies *ownership* deterministically against the sheet (not AI).
    #      This means prompt rules can never cause a false rejection — if the model
    #      keeps mis-classifying a tactical phrase ("surprise attack"), the Ruby
    #      lookup simply won't find it on the sheet and the fallback is allow.
    #
    #   B) World Consistency Check — validates that the entities, targets, or
    #      objects the player references actually exist in the current scene.
    #      AI-only for the same reason: scene state lives in prose context.
    #      Runs ALWAYS (via full gate or standalone).
    #
    # When both run together (full gate with sheet), they use Node POST /fan_out
    # — no Ruby Thread.new.
    module SanityChecker
      # Tactical phrases the extractor may mis-classify as named abilities.
      # When a false rejection is observed in play logs, add the normalized
      # lowercase name here instead of adjusting the prompt.
      # The architecture guarantees this is the only place that ever needs
      # to change for this class of problem.
      TACTICAL_PHRASE_IGNORE = %w[
        surprise\ attack
        sneak\ up
        ambush
        backstab
        feint
        charging\ attack
        flanking\ attack
      ].freeze

      private

      # World + capability in one evaluator round-trip (`AdventureLoopResolution#resolve` → here).
      def run_sanity_gate_fan_out(intent)
        text = intent[:intention]
        prompts = [sanity_checker_world_evaluator_prompt(intent)]
        prompts << sanity_checker_capability_evaluator_prompt(intent) if @sheet

        by_step = evaluator_fan_out!(prompts, text, phase: "sanity_gate")

        world = parse_world_from_evaluator_result(
          evaluator_fan_out_result!(by_step, "sanity_checker_world", "sanity_gate"))
        capability = if @sheet
                       parse_capability_from_evaluator_result(
                         evaluator_fan_out_result!(by_step, "sanity_checker", "sanity_gate"))
                     else
                       { allowed: true, reason: nil }
                     end
        [world, capability]
      end

      def sanity_checker_world_evaluator_prompt(intent)
        prompt_context = build_world_prompt_context

        system_prompt = PromptRenderer.render("sanity_checker_world",
          sanity_context: prompt_context)

        EvaluatorPromptPayload.new(
          system_prompt: system_prompt,
          user_message: intent[:intention],
          model: @config.model_for("sanity_checker_world"),
          max_tokens: @config.token_budget_for("sanity_checker_world"),
          step: "sanity_checker_world"
        ).to_h
      end

      def sanity_checker_capability_evaluator_prompt(intent)
        prompt_context = build_capability_prompt_context

        system_prompt = PromptRenderer.render("sanity_checker",
          sanity_context: prompt_context)

        EvaluatorPromptPayload.new(
          system_prompt: system_prompt,
          user_message: intent[:intention],
          model: @config.model_for("sanity_checker"),
          max_tokens: @config.token_budget_for("sanity_checker"),
          step: "sanity_checker"
        ).to_h
      end

      def parse_world_from_evaluator_result(result)
        parsed = result["parsed_response"] || {}
        {
          consistent: parsed["consistent"] != false,
          reason: parsed["reason"],
          dm_message: parsed["dm_message"],
          referenced_entities: Array(parsed["referenced_entities"])
        }
      end

      def parse_capability_from_evaluator_result(result)
        parsed = result["parsed_response"] || {}
        ability_uses      = Array(parsed["ability_uses"]).map(&:deep_symbolize_keys)
        condition_violated = parsed["condition_violated"]
        check_extracted_abilities(ability_uses, condition_violated)
      end

      # ------------------------------------------------------------------
      # Rejection payloads (AdventureLoopResolution orchestration — logging + result hash)
      # ------------------------------------------------------------------

      def world_check_rejection(intent, world)
        @log.play_log!("world_check_failure", "SanityChecker world check failed: #{world[:reason]}")
        @loop&.log_step("sanity_checker", "World check FAILED: #{world[:reason].to_s.truncate(100)}")
        PipelineFlowResults.rejected(intent: intent, reason: world[:reason], dm_message: world[:dm_message]).to_h
      end

      def capability_check_rejection(intent, capability)
        @log.play_log!("capability_rejection", "SanityChecker capability check failed: #{capability[:reason]}")
        @loop&.log_step("sanity_checker", "Capability check FAILED: #{capability[:reason].to_s.truncate(100)}")
        PipelineFlowResults.rejected(intent: intent, reason: capability[:reason]).to_h
      end

      # ------------------------------------------------------------------
      # Sub-task A: Capability Check (spells / feats / items vs sheet)
      # ------------------------------------------------------------------

      def run_capability_check(intent)
        return { allowed: true, reason: nil } unless @sheet

        prompt_summary = "SanityChecker/capability: \"#{@log.truncate(intent[:intention])}\""
        prompt_context = build_capability_prompt_context

        system_prompt = PromptRenderer.render("sanity_checker",
          sanity_context: prompt_context)

        request_body = { system_prompt: system_prompt, user_message: intent[:intention] }

        parsed = timed_ai_call("sanity_checker", prompt_summary, request_body) do
          raw_response = @ai.chat(system_prompt: system_prompt, user_message: intent[:intention],
                                  max_tokens: @config.token_budget_for("sanity_checker"),
                                  step_name: "sanity_checker",
                                  model: @config.model_for("sanity_checker"))
          [raw_response, @ai.parse_json(raw_response)]
        end

        ability_uses       = Array(parsed["ability_uses"]).map(&:deep_symbolize_keys)
        condition_violated = parsed["condition_violated"]
        check_extracted_abilities(ability_uses, condition_violated)
      end

      # ------------------------------------------------------------------
      # Deterministic capability verdict — called by both the fan-out and
      # the direct AI call paths after parsing the extraction response.
      # ------------------------------------------------------------------

      def check_extracted_abilities(ability_uses, condition_violated)
        return { allowed: false, reason: condition_violated } if condition_violated.present?

        ability_uses = ability_uses.reject do |u|
          TACTICAL_PHRASE_IGNORE.include?(TextNormalizer.normalized_key(u[:name]))
        end

        return { allowed: true, reason: nil } if ability_uses.empty?

        lookup  = sheet_ability_lookup
        missing = ability_uses.reject { |u| ability_on_sheet?(u[:name], u[:type], lookup) }
        if missing.any?
          names = missing.map { |u| u[:name] }.join(", ")
          { allowed: false, reason: "#{names} not found on character sheet" }
        else
          { allowed: true, reason: nil }
        end
      end

      def sheet_ability_lookup
        {
          spells:          @sheet.spell_definitions.map          { |spell| TextNormalizer.normalized_key(spell.name) },
          feats:           @sheet.feat_definitions.map           { |feat| TextNormalizer.normalized_key(feat.name) },
          items:           @sheet.item_definitions.map           { |item| TextNormalizer.normalized_key(item.name) },
          class_abilities: @sheet.class_ability_definitions.map  { |ability| TextNormalizer.normalized_key(ability.name) },
          class_ability_registry_seeded: ClassAbilityDefinition.exists?
        }
      end

      def ability_on_sheet?(name, type, lookup)
        normalized_name = TextNormalizer.normalized_key(name)
        case type.to_s
        when "spell"   then lookup[:spells].include?(normalized_name)
        when "feat"    then lookup[:feats].include?(normalized_name)
        when "item"    then lookup[:items].include?(normalized_name)
        when "ability"
          # Two distinct states:
          #   - Global registry empty (data migration not yet run): permissive fallback.
          #   - Registry seeded but this sheet has no matching class ability: reject.
          return true unless lookup[:class_ability_registry_seeded]

          lookup[:class_abilities].include?(normalized_name)
        else
          lookup[:spells].include?(normalized_name) ||
            lookup[:feats].include?(normalized_name) ||
            lookup[:items].include?(normalized_name)
        end
      end

      # ------------------------------------------------------------------
      # Sub-task B: World Consistency Check (scene state validation)
      # ------------------------------------------------------------------

      def run_world_consistency_check(intent)
        prompt_summary = "SanityChecker/world: \"#{@log.truncate(intent[:intention])}\""

        prompt_context = build_world_prompt_context

        system_prompt = PromptRenderer.render("sanity_checker_world",
          sanity_context: prompt_context)

        request_body = { system_prompt: system_prompt, user_message: intent[:intention] }

        parsed = timed_ai_call("sanity_checker_world", prompt_summary, request_body) do
          raw_response = @ai.chat(system_prompt: system_prompt, user_message: intent[:intention],
                                  max_tokens: @config.token_budget_for("sanity_checker_world"),
                                  step_name: "sanity_checker_world",
                                  model: @config.model_for("sanity_checker_world"))
          [raw_response, @ai.parse_json(raw_response)]
        end

        {
          consistent: parsed["consistent"] != false,
          reason: parsed["reason"],
          dm_message: parsed["dm_message"],
          referenced_entities: Array(parsed["referenced_entities"])
        }
      end

      def build_capability_prompt_context
        derived_stats = @sheet&.derived_stats || {}
        PromptViews::SanityCheckerPromptContext.new(
          condition_restrictions: derived_stats["condition_restrictions"]
        )
      end

      def build_world_prompt_context
        combat_ctx = @adventure.combat_context || {}
        combat_active = combat_ctx["active"] == true
        combat_roster = combat_active ? Array(combat_ctx["participants"]).filter_map { |p| p["name"] } : []

        PromptViews::SanityCheckerPromptContext.new(
          scene_summary: @adventure.scene_summary,
          scene_history: @adventure.scene_history,
          micro_contexts: PromptHelpers.all_micro_contexts(@adventure),
          npc_names: @adventure.story.story_npcs.pluck(:name),
          combat_active: combat_active,
          combat_turn_order: combat_roster
        )
      end
    end
  end
end
