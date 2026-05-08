# frozen_string_literal: true

module DungeonMaster
  module Steps
    module ContextUpdate
      COMBAT_DOMAIN_STEP = "combat_context_update"

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

      def run_context_updates(what_happened, mutations, allow_combat_initialization: true)
        broadcast_progress("Remembering the world...")
        context_result = run_context_update_fan_out(
          what_happened, mutations,
          allow_combat_initialization: allow_combat_initialization,
        )

        apply_context_update_results(context_result,
          mutations: mutations)
      rescue => e
        pipeline_error!("context_updates", e)
      end

      # Used by Stagehand parallel narrative (narrate + context in one fan_out).
      def apply_context_update_results(context_result, mutations:)
        persist_combat_context(context_result, mutations)
        handle_new_creatures(context_result["new_creatures"]) if context_result["new_creatures"].present?
      end

      def run_context_update_fan_out(what_happened, mutations, allow_combat_initialization:)
        prompts = build_context_update_prompts(what_happened, mutations,
          allow_combat_initialization: allow_combat_initialization)

        by_step = evaluator_fan_out!(prompts, what_happened, phase: "context_update")

        aggregate_context_update_results(by_step)
      end

      def persist_combat_context(parsed, mutations = nil)
        prev_combat = @adventure.combat_context
        prev_active = prev_combat.is_a?(Hash) ? prev_combat["active"] : nil
        combat_mutation_state = CombatMutationState.new(mutations)

        domain_context_result = parsed["combat_context"] || parsed[:combat_context]
        canonical_combat = combat_mutation_state.canonical_combat_context

        return snapshot_contexts_to_loop unless domain_context_result.present? || canonical_combat.present?

        domain_result_parser = DomainContextResultParser.new(
          domain_identifier: "combat",
          raw_domain_result: domain_context_result || {}
        )
        normalized_domain_result = domain_result_parser.normalized_result

        unchanged = normalized_domain_result["unchanged"] == true
        existing_domain_context = (@adventure.combat_context || {}).deep_stringify_keys
        return snapshot_contexts_to_loop if unchanged && canonical_combat.blank?

        updated_domain_context = normalized_domain_result["context"] || normalized_domain_result[:context]
        updated_domain_context = {} if unchanged && canonical_combat.present? && updated_domain_context.nil?
        raise Ai::Error, "combat_context updater returned no context payload" if updated_domain_context.nil?

        if updated_domain_context.is_a?(Hash)
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
          return snapshot_contexts_to_loop unless updated_domain_context.present?

          unless combat_mutation_state.has_combat_initialization?
            updated_domain_context = existing_domain_context.deep_merge(updated_domain_context)
          end
        end

        @adventure.update!(combat_context: updated_domain_context)
        @adventure.reload

        if combat_just_deactivated?(prev_active: prev_active, combat_context: @adventure.combat_context)
          Battlefield::ArchiveCombatEnd.call(adventure: @adventure)
        end

        snapshot_contexts_to_loop
      end

      def build_context_update_prompts(what_happened, mutations, allow_combat_initialization:)
        [
          combat_domain_evaluator_prompt(what_happened, mutations,
            allow_combat_initialization: allow_combat_initialization),
        ]
      end

      def combat_domain_evaluator_prompt(what_happened, mutations, allow_combat_initialization:)
        system_prompt = Ai::PromptRenderer.render("combat_context_update",
          domain: "combat",
          context_key: "combat_context",
          current_context: @adventure.combat_context,
          context_schema: Ai::PromptRenderer.load_schema("contexts/combat_context"),
          what_happened: what_happened,
          mutations_json: mutations.present? ? mutations.to_json : nil,
          canonical_hp: build_canonical_hp,
          canonical_participants: canonical_combat_participants,
          allow_combat_initialization: allow_combat_initialization)

        {
          system_prompt: system_prompt,
          user_message: what_happened,
          model: @config.model_for(COMBAT_DOMAIN_STEP),
          meta: { step: COMBAT_DOMAIN_STEP, domain: "combat" }
        }
      end

      def aggregate_context_update_results(by_step)
        combat_parsed = evaluator_fan_out_result!(by_step, COMBAT_DOMAIN_STEP, "context_update")["parsed_response"] || {}

        domain_result_parser = DomainContextResultParser.new(
          domain_identifier: "combat",
          raw_domain_result: combat_parsed
        )
        { "combat_context" => domain_result_parser.normalized_result }
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
          raise Ai::Error, "Combat context update dropped creature_sheet_id for #{row['name'].presence || 'an NPC'}"
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

      def merge_canonical_combat_context(val, canonical_combat:)
        return val if canonical_combat.blank?

        val.deep_merge(canonical_combat.deep_stringify_keys)
      end

      def snapshot_contexts_to_loop
        return unless @loop

        @loop.batch_update!(new_data: {
          "context_snapshot" => {
            "combat_context" => @adventure.combat_context,
            "time_context"   => @adventure.time_context,
          }
        })
      end

      def combat_just_deactivated?(prev_active:, combat_context:)
        combat_context.is_a?(Hash) &&
          prev_active == true &&
          combat_context["active"] == false
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
    end
  end
end
