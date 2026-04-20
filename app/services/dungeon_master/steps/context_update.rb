# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step 6a/6b: Context updates.
    # 6a — Micro context update (self-directed: reads outcome, decides which domains changed)
    # 6b — Macro narrative update (story summary)
    # When macro_significant, 6a+6b run via Node POST /fan_out (no Ruby threads).
    #
    # ContextUpdate is the sole writer of all Adventure context fields.
    # It receives what_happened (the full outcome text) and decides independently
    # which of the six domains to update. No upstream affected_contexts signal is
    # used — the AI reads the outcome and makes that judgment itself.
    module ContextUpdate
      DEEP_MERGE_CONTEXT_FIELDS = %w[combat].freeze
      META_CONTEXT_STEP = "meta_context_update"

      class CombatMutationState
        def initialize(mutations)
          @mutations = mutations.is_a?(Hash) ? mutations.deep_stringify_keys : {}
        end

        def has_combat_initialization?
          @mutations["combat_initialization"].is_a?(Hash)
        end

        def has_combat_advancement?
          @mutations["combat_state_advancement"].is_a?(Hash)
        end

        def canonical_combat_context
          @mutations["combat_initialization"] || @mutations["combat_state_advancement"]
        end
      end

      private

      def run_context_updates(what_happened, mutations, macro_significant: false, allow_combat_initialization: true)
        broadcast_progress("Remembering the world...")
        micro_result, macro_result = if macro_significant
                                       run_context_updates_fan_out(what_happened, mutations,
                                         allow_combat_initialization: allow_combat_initialization)
                                     else
                                       [run_micro_context_update(what_happened, mutations,
                                         allow_combat_initialization: allow_combat_initialization), {}]
                                     end

        apply_context_update_results(micro_result, macro_result,
          macro_significant: macro_significant,
          mutations: mutations)
      rescue => e
        pipeline_error!("context_updates", e)
      end

      # Used by Stagehand parallel narrative (narrate + context in one fan_out).
      def apply_context_update_results(micro_result, macro_result, macro_significant:, mutations:)
        persist_micro_contexts(micro_result, mutations)
        persist_scene_summary(micro_result["scene_summary"])
        handle_new_creatures(micro_result["new_creatures"]) if micro_result["new_creatures"].present?
        handle_context_wishes(micro_result["context_wishes"]) if micro_result["context_wishes"].present?

        if should_persist_macro_story_summary?(macro_significant, macro_result)
          @adventure.update!(story_summary: macro_result["story_summary"])
        end
      end

      def run_context_updates_fan_out(what_happened, mutations, allow_combat_initialization:)
        prompts = build_micro_context_updater_prompts(what_happened, mutations,
          allow_combat_initialization: allow_combat_initialization)
        prompts << macro_context_evaluator_prompt(what_happened)
        by_step = evaluator_fan_out!(prompts, what_happened, phase: "context_update")
        micro_parsed = aggregate_micro_context_results(by_step)
        macro_parsed = evaluator_fan_out_result!(by_step, "macro_narrative_update", "context_update")["parsed_response"] || {}
        [micro_parsed, macro_parsed]
      end

      def macro_context_evaluator_prompt(what_happened)
        system_prompt, user_msg = PromptRenderer.render_with_user_message("macro_narrative_update",
          story_intro: @adventure.story.preview,
          story_summary: @adventure.story_summary,
          what_happened: what_happened)

        {
          system_prompt: system_prompt,
          user_message:  user_msg,
          model:         @config.model_for("macro_narrative_update"),
          max_tokens:    @config.token_budget_for("macro_narrative_update"),
          meta:          { step: "macro_narrative_update" }
        }
      end

      def run_micro_context_update(what_happened, mutations, allow_combat_initialization: true)
        aggregate_micro_context_results(
          run_micro_context_updates_fan_out(what_happened, mutations,
            allow_combat_initialization: allow_combat_initialization)
        )
      end

      def run_macro_narrative_update(what_happened)
        prompt_summary = "Macro narrative update"

        system_prompt, user_msg = PromptRenderer.render_with_user_message("macro_narrative_update",
          story_intro: @adventure.story.preview,
          story_summary: @adventure.story_summary,
          what_happened: what_happened)

        request_body = { system_prompt: system_prompt, user_message: user_msg }

        timed_ai_call("macro_narrative_update", prompt_summary, request_body) do
          ai_raw_response_text = @ai.chat(system_prompt: system_prompt, user_message: user_msg,
                                          max_tokens: @config.token_budget_for("macro_narrative_update"),
                                          step_name: "macro_narrative_update",
                                          model: @config.model_for("macro_narrative_update"))
          [ai_raw_response_text, @ai.parse_json(ai_raw_response_text)]
        end
      end

      def persist_micro_contexts(parsed, mutations = nil)
        prev_combat = @adventure.combat_context
        prev_active = prev_combat.is_a?(Hash) ? prev_combat["active"] : nil
        combat_mutation_state = CombatMutationState.new(mutations)

        updates = PromptHelpers::CONTEXT_FIELDS.each_with_object({}) do |field, updated_contexts|
          domain_context_identifier = "#{field}_context"
          domain_context_result = parsed[domain_context_identifier] || parsed[domain_context_identifier.to_sym]
          next unless domain_context_result.present?

          domain_result_parser = DomainContextResultParser.new(
            domain_identifier: field,
            raw_domain_result: domain_context_result
          )
          normalized_domain_result = domain_result_parser.normalized_result

          unchanged = normalized_domain_result["unchanged"] == true
          existing_domain_context = (@adventure.public_send(domain_context_identifier) || {}).deep_stringify_keys
          canonical_combat = canonical_combat_context_for(field, combat_mutation_state)
          next if unchanged && canonical_combat.blank?

          updated_domain_context = normalized_domain_result["context"] || normalized_domain_result[:context]
          updated_domain_context = {} if unchanged && canonical_combat.present? && updated_domain_context.nil?
          raise AiError, "#{domain_context_identifier} updater returned no context payload" if updated_domain_context.nil?

          if DEEP_MERGE_CONTEXT_FIELDS.include?(field) && updated_domain_context.is_a?(Hash)
            updated_domain_context = merge_canonical_combat_context(
              updated_domain_context.deep_stringify_keys,
              canonical_combat: canonical_combat
            )
            updated_domain_context = prepare_combat_context_update(
              updated_domain_context.deep_stringify_keys,
              existing: existing_domain_context
            )
            updated_domain_context = guard_combat_context_update(
              updated_domain_context.deep_stringify_keys,
              prev_active: prev_active,
              has_combat_initialization: combat_mutation_state.has_combat_initialization?,
              has_combat_advancement: combat_mutation_state.has_combat_advancement?
            )
            next unless updated_domain_context.present?

            unless combat_mutation_state.has_combat_initialization?
              updated_domain_context = existing_domain_context.deep_merge(updated_domain_context)
            end
          end
          updated_contexts[domain_context_identifier.to_sym] = updated_domain_context
        end
        @adventure.update!(updates) if updates.any?

        if updates.key?(:combat_context)
          @adventure.reload
          combat_context = @adventure.combat_context
          if combat_just_deactivated?(prev_active: prev_active, combat_context: combat_context)
            Battlefield::ArchiveCombatEnd.call(adventure: @adventure)
          end
        end

        snapshot_contexts_to_loop
      end

      def build_micro_context_updater_prompts(what_happened, mutations, allow_combat_initialization:)
        domain_prompts = PromptHelpers::CONTEXT_FIELDS.map do |field|
          domain_context_evaluator_prompt(field, what_happened, mutations,
            allow_combat_initialization: allow_combat_initialization)
        end
        domain_prompts + [meta_context_evaluator_prompt(what_happened)]
      end

      def run_micro_context_updates_fan_out(what_happened, mutations, allow_combat_initialization:)
        prompts = build_micro_context_updater_prompts(what_happened, mutations,
          allow_combat_initialization: allow_combat_initialization)
        evaluator_fan_out!(prompts, what_happened, phase: "micro_context_update")
      end

      def domain_context_evaluator_prompt(field, what_happened, mutations, allow_combat_initialization:)
        key = "#{field}_context"
        template_name = field == "combat" ? "micro_context_domain_update_combat" : "micro_context_domain_update"
        system_prompt = PromptRenderer.render(template_name,
          domain: field,
          context_key: key,
          current_context: @adventure.public_send(key),
          context_schema: PromptRenderer.load_schema("contexts/#{key}"),
          what_happened: what_happened,
          mutations_json: mutations.present? ? mutations.to_json : nil,
          canonical_hp: build_canonical_hp,
          canonical_participants: field == "combat" ? canonical_combat_participants : nil,
          allow_combat_initialization: allow_combat_initialization)

        step = "#{field}_context_update"
        {
          system_prompt: system_prompt,
          # We intentionally pass the same narrated seed to every domain updater;
          # if we ever add domain-specific slicing, this is the seam to change.
          user_message: what_happened,
          model: @config.model_for(step),
          max_tokens: @config.token_budget_for(step),
          meta: { step: step, domain: field }
        }
      end

      def meta_context_evaluator_prompt(what_happened)
        system_prompt = PromptRenderer.render("micro_context_meta_update",
          what_happened: what_happened,
          scene_summary: @adventure.scene_summary,
          context_wishes: [])

        {
          system_prompt: system_prompt,
          # Meta context uses the same seed as the domain fan-out for consistency.
          user_message: what_happened,
          model: @config.model_for(META_CONTEXT_STEP),
          max_tokens: @config.token_budget_for(META_CONTEXT_STEP),
          meta: { step: META_CONTEXT_STEP }
        }
      end

      def aggregate_micro_context_results(by_step)
        PromptHelpers::CONTEXT_FIELDS.each_with_object({}) do |field, aggregated_results|
          domain_context_identifier = "#{field}_context"
          parsed_fan_out_response = evaluator_fan_out_result!(
            by_step,
            "#{field}_context_update",
            "micro_context_update"
          )["parsed_response"] || {}
          domain_result_parser = DomainContextResultParser.new(
            domain_identifier: field,
            raw_domain_result: parsed_fan_out_response
          )
          aggregated_results[domain_context_identifier] = domain_result_parser.normalized_result
        end.merge(
          evaluator_fan_out_result!(by_step, META_CONTEXT_STEP, "micro_context_update")["parsed_response"] || {}
        )
      end

      def should_persist_macro_story_summary?(macro_significant, macro_result)
        macro_significant && macro_result["story_summary"].present?
      end

      def prepare_combat_context_update(val, existing:)
        participants = Array(val["participants"])
        return val if participants.empty?

        existing_participants = Array(existing["participants"])
        repaired = participants.map do |participant|
          repair_combat_participant_identity(participant, existing_participants)
        end
        val.merge("participants" => repaired)
      end

      def repair_combat_participant_identity(participant, existing_participants)
        row = participant.is_a?(Hash) ? participant.deep_stringify_keys : {}
        return row unless row["type"].to_s == "npc"

        return row if row["creature_sheet_id"].present?

        matched = existing_participants.find do |existing|
          existing["type"].to_s == "npc" && existing["name"].to_s == row["name"].to_s && existing["creature_sheet_id"].present?
        end
        matched ||= @adventure.creature_sheets.where(name: row["name"].to_s).yield_self do |rel|
          rel.one? ? { "creature_sheet_id" => rel.first.id } : nil
        end

        repaired = matched&.[]("creature_sheet_id")
        if repaired.present?
          row.merge("creature_sheet_id" => repaired)
        else
          raise AiError, "Combat context update dropped creature_sheet_id for #{row['name'].presence || 'an NPC'}"
        end
      end

      def guard_combat_context_update(val, prev_active:, has_combat_initialization:, has_combat_advancement:)
        if has_combat_initialization
          return val
        end

        if has_combat_advancement
          return val if prev_active == true

          @log.play_log!("combat_context_guard",
            "Ignored combat_state_advancement while combat inactive")
          return nil
        end

        if prev_active != true && val["active"] == true
          @log.play_log!("combat_context_guard",
            "Ignored synthetic combat activation without combat_initialization")
          return nil
        end

        val
      end

      def canonical_combat_context_for(field, combat_mutation_state)
        return nil unless field == "combat"

        combat_mutation_state.canonical_combat_context
      end

      def merge_canonical_combat_context(val, canonical_combat:)
        return val if canonical_combat.blank?

        val.deep_merge(canonical_combat.deep_stringify_keys)
      end

      def snapshot_contexts_to_loop
        return unless @loop

        snapshot = PromptHelpers::CONTEXT_FIELDS.each_with_object({}) do |field, h|
          key = "#{field}_context"
          h[key] = @adventure.public_send(key)
        end

        @loop.batch_update!(new_data: { "context_snapshot" => snapshot })
      end

      def combat_just_deactivated?(prev_active:, combat_context:)
        combat_context.is_a?(Hash) &&
          prev_active == true &&
          combat_context["active"] == false
      end

      def persist_scene_summary(summary)
        return unless summary.present?

        max_history = (@config.get("scene_history_depth") || 10).to_i
        history = Array(@adventure.scene_history)
        history.push({ "summary" => summary, "at" => Time.current.iso8601 })
        history = history.last(max_history)

        @adventure.update!(scene_summary: summary, scene_history: history)
      end

      def build_canonical_hp
        lines = []
        lines << "Player: #{@sheet.hp}/#{@sheet.max_hp}" if @sheet

        @adventure.creature_sheets.each do |c|
          lines << "#{c.name}: #{c.hp}/#{c.max_hp}"
        end

        lines.any? ? lines.join("\n") : nil
      end

      def canonical_combat_participants
        combat_context = @adventure.combat_context
        return [] unless combat_context.is_a?(Hash)

        Array(combat_context["participants"]).map(&:deep_stringify_keys)
      end

      # Log context wishes emitted by the AI when the outcome touches something
      # that doesn't map cleanly to the existing six domain fields. These are
      # observability signals for future context domain design, visible in the
      # admin play log UI under event_type "context_wish".
      def handle_context_wishes(wishes)
        Array(wishes).each do |wish|
          next unless wish.is_a?(String) && wish.present?
          @log.play_log!("context_wish", wish)
        end
      end
    end
  end
end
