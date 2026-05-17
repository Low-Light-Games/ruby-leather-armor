# frozen_string_literal: true

module PlayerTurn
  module Steps
    module SanityChecker
      TACTICAL_PHRASE_IGNORE = [
        'surprise attack',
        'sneak up',
        'ambush',
        'backstab',
        'feint',
        'charging attack',
        'flanking attack'
      ].freeze

      private

      def run_sanity_gate_fan_out(result)
        text = result.intention
        broadcast_progress('Reality is checking the premise...')

        prompts = [sanity_checker_world_evaluator_prompt(result)]
        prompts << sanity_checker_capability_evaluator_prompt(result) if @sheet

        by_step = evaluator_fan_out!(prompts, text, phase: 'sanity_gate')

        world = parse_world_from_evaluator_result(
          evaluator_fan_out_result!(by_step, 'sanity_checker_world', 'sanity_gate')
        )
        capability = if @sheet
                       parse_capability_from_evaluator_result(
                         evaluator_fan_out_result!(by_step, 'sanity_checker', 'sanity_gate')
                       )
                     else
                       CapabilityCheckResult.new(allowed: true, reason: nil).to_h
                     end
        [world, capability]
      end

      def sanity_checker_world_evaluator_prompt(result)
        prompt_context = build_world_prompt_context(intention: result.intention)

        system_prompt = Ai::PromptRenderer.render('sanity_checker_world',
                                              sanity_context: prompt_context)

        EvaluatorPromptPayload.new(
          system_prompt:    system_prompt,
          user_message:     result.intention,
          model:            @config.model_for('sanity_checker_world'),
          step:             'sanity_checker_world',
          reasoning_effort: @config.reasoning_effort_for('sanity_checker_world')
        ).to_h
      end

      def sanity_checker_capability_evaluator_prompt(result)
        prompt_context = build_capability_prompt_context

        system_prompt = Ai::PromptRenderer.render('sanity_checker',
                                              sanity_context: prompt_context)

        EvaluatorPromptPayload.new(
          system_prompt:    system_prompt,
          user_message:     result.intention,
          model:            @config.model_for('sanity_checker'),
          step:             'sanity_checker',
          reasoning_effort: @config.reasoning_effort_for('sanity_checker')
        ).to_h
      end

      def parse_world_from_evaluator_result(result)
        parsed = result['parsed_response'] || {}
        WorldConsistencyResult.new(
          consistent: parsed['consistent'] != false,
          reason: parsed['reason'],
          dm_message: parsed['dm_message'],
          referenced_entities: Array(parsed['referenced_entities'])
        ).to_h
      end

      def parse_capability_from_evaluator_result(result)
        parsed = result['parsed_response'] || {}
        ability_uses = ::PlayerTurn::Rolls::HashArray.symbolize_strict(parsed['ability_uses'])
        condition_violated = parsed['condition_violated']
        check_extracted_abilities(ability_uses, condition_violated)
      end

      def world_check_rejection(intent, world)
        @log.play_log!('world_check_failure', "SanityChecker world check failed: #{world[:reason]}")
        @loop&.log_step('sanity_checker', "World check FAILED: #{world[:reason].to_s.truncate(100)}")
        FlowResults.rejected(intent: intent, reason: world[:reason], dm_message: world[:dm_message]).to_h
      end

      def capability_check_rejection(intent, capability)
        @log.play_log!('capability_rejection', "SanityChecker capability check failed: #{capability[:reason]}")
        @loop&.log_step('sanity_checker', "Capability check FAILED: #{capability[:reason].to_s.truncate(100)}")
        FlowResults.rejected(intent: intent, reason: capability[:reason]).to_h
      end

      def run_capability_check(result)
        return CapabilityCheckResult.new(allowed: true, reason: nil).to_h unless @sheet

        broadcast_progress('Reality is checking the character sheet...')

        intention = result.intention
        prompt_summary = "SanityChecker/capability: \"#{@log.truncate(intention)}\""
        prompt_context = build_capability_prompt_context

        system_prompt = Ai::PromptRenderer.render('sanity_checker',
                                              sanity_context: prompt_context)

        request_body = { system_prompt: system_prompt, user_message: intention }

        parsed = timed_ai_call('sanity_checker', prompt_summary, request_body) do
          raw_response = @ai.chat(system_prompt: system_prompt, user_message: intention,
                                  step_name: 'sanity_checker',
                                  model: @config.model_for('sanity_checker'))
          [raw_response, @ai.parse_json(raw_response)]
        end

        ability_uses       = ::PlayerTurn::Rolls::HashArray.symbolize_strict(parsed['ability_uses'])
        condition_violated = parsed['condition_violated']
        check_extracted_abilities(ability_uses, condition_violated)
      end

      def check_extracted_abilities(ability_uses, condition_violated)
        return CapabilityCheckResult.new(allowed: false, reason: condition_violated).to_h if condition_violated.present?

        ability_uses = ability_uses.reject do |u|
          TACTICAL_PHRASE_IGNORE.include?(Transformers::TextNormalizer.normalized_key(u[:name]))
        end

        return CapabilityCheckResult.new(allowed: true, reason: nil).to_h if ability_uses.empty?

        lookup  = sheet_ability_lookup
        missing = ability_uses.reject { |u| ability_on_sheet?(u[:name], u[:type], lookup) }
        if missing.any?
          names = missing.map { |u| u[:name] }.join(', ')
          CapabilityCheckResult.new(
            allowed: false,
            reason: "#{names} not found on character sheet"
          ).to_h
        else
          CapabilityCheckResult.new(allowed: true, reason: nil).to_h
        end
      end

      def sheet_ability_lookup
        {
          spells: @sheet.spell_definitions.map { |spell| Transformers::TextNormalizer.normalized_key(spell.name) },
          feats: @sheet.feat_definitions.map           { |feat| Transformers::TextNormalizer.normalized_key(feat.name) },
          items: @sheet.item_definitions.map           { |item| Transformers::TextNormalizer.normalized_key(item.name) },
          class_abilities: @sheet.class_ability_definitions.map do |ability|
            Transformers::TextNormalizer.normalized_key(ability.name)
          end,
          class_ability_registry_seeded: ClassAbilityDefinition.exists?
        }
      end

      def ability_on_sheet?(name, type, lookup)
        normalized_name = Transformers::TextNormalizer.normalized_key(name)
        case type.to_s
        when 'spell'   then lookup[:spells].include?(normalized_name)
        when 'feat'    then lookup[:feats].include?(normalized_name)
        when 'item'    then lookup[:items].include?(normalized_name)
        when 'ability'
          return true unless lookup[:class_ability_registry_seeded]

          lookup[:class_abilities].include?(normalized_name)
        else
          lookup[:spells].include?(normalized_name) ||
            lookup[:feats].include?(normalized_name) ||
            lookup[:items].include?(normalized_name)
        end
      end

      def run_world_consistency_check(result)
        intention = result.intention
        prompt_summary = "SanityChecker/world: \"#{@log.truncate(intention)}\""

        prompt_context = build_world_prompt_context(intention: intention)

        system_prompt = Ai::PromptRenderer.render('sanity_checker_world',
                                              sanity_context: prompt_context)

        request_body = { system_prompt: system_prompt, user_message: intention }

        parsed = timed_ai_call('sanity_checker_world', prompt_summary, request_body) do
          raw_response = @ai.chat(system_prompt: system_prompt, user_message: intention,
                                  step_name: 'sanity_checker_world',
                                  model: @config.model_for('sanity_checker_world'))
          [raw_response, @ai.parse_json(raw_response)]
        end

        WorldConsistencyResult.new(
          consistent: parsed['consistent'] != false,
          reason: parsed['reason'],
          dm_message: parsed['dm_message'],
          referenced_entities: Array(parsed['referenced_entities'])
        ).to_h
      end

      def build_capability_prompt_context
        derived_stats = @sheet&.derived_stats || {}
        PromptViews::SanityCheckerPromptContext.new(
          condition_restrictions: derived_stats['condition_restrictions']
        )
      end

      def build_world_prompt_context(intention:)
        combat_state = Adventures::CombatState.from_adventure(@adventure)

        PromptViews::SanityCheckerPromptContext.new(
          established_facts: retrieve_established_facts(intention),
          nearby_npcs: retrieve_nearby_npcs(intention),
          nearby_locations: retrieve_nearby_locations(intention),
          combat_active: combat_state.active?,
          combat_turn_order: combat_state.participant_names
        )
      end

      def retrieve_established_facts(intention)
        Lore::FactsLookup.call(
          adventure: @adventure,
          ai: @ai,
          log: @log,
          query_text: intention
        )
      end

      def retrieve_nearby_npcs(intention)
        Lore::NpcsLookup.call(
          adventure: @adventure,
          ai: @ai,
          log: @log,
          query_text: intention
        )
      end

      def retrieve_nearby_locations(intention)
        Lore::LocationsLookup.call(
          adventure: @adventure,
          ai: @ai,
          log: @log,
          query_text: intention
        )
      end
    end
  end
end
