# frozen_string_literal: true

module PlayerTurn
  module Steps
    module ContextUpdate
      STEP_NAME = "combat_context_update"

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

      class Result
        attr_reader :context

        def self.from_parsed(parsed)
          hash = parsed.is_a?(Hash) ? parsed.deep_stringify_keys : {}
          new(unchanged: hash["unchanged"] == true, context: hash["context"])
        end

        def initialize(unchanged:, context:)
          @unchanged = unchanged
          @context   = context
        end

        def unchanged? = @unchanged
      end

      private

      def run_context_updates(what_happened, mutations, allow_combat_initialization: true)
        broadcast_progress("Remembering the world...")
        prompts = [combat_context_evaluator_prompt(what_happened, mutations,
          allow_combat_initialization: allow_combat_initialization)]
        by_step = evaluator_fan_out!(prompts, what_happened, phase: "context_update")
        persist_combat_context(combat_context_result(by_step, phase: "context_update"), mutations)
      rescue => e
        pipeline_error!("context_updates", e)
      end

      # @param by_step [Hash] evaluator fan_out result
      # @param phase   [String] phase label (used in error messages)
      def combat_context_result(by_step, phase:)
        Result.from_parsed(evaluator_fan_out_result!(by_step, STEP_NAME, phase)["parsed_response"])
      end

      def persist_combat_context(result, mutations)
        prev_combat = @adventure.combat_context
        prev_active = prev_combat.is_a?(Hash) ? prev_combat["active"] : nil
        combat_mutation_state = CombatMutationState.new(mutations)
        canonical_combat = combat_mutation_state.canonical_combat_context

        return snapshot_contexts_to_loop unless result.context.present? || canonical_combat.present?

        return snapshot_contexts_to_loop if result.unchanged? && canonical_combat.blank?


        updated = result.context || (canonical_combat.present? ? {} : nil)
        raise Ai::Error, "combat_context updater returned no context payload" if updated.nil?

        if updated.is_a?(Hash)
          existing = (@adventure.combat_context || {}).deep_stringify_keys
          updated = merge_canonical_combat_context(updated.deep_stringify_keys, canonical_combat: canonical_combat)
          updated = repair_participant_identities(updated.deep_stringify_keys, existing: existing)
          updated = guard_combat_context_update(
            updated.deep_stringify_keys,
            prev_active: prev_active,
            combat_mutation_state: combat_mutation_state
          )
          return snapshot_contexts_to_loop unless updated.present?

          updated = existing.deep_merge(updated) unless combat_mutation_state.has_combat_initialization?
        end

        @adventure.update!(combat_context: updated)
        @adventure.reload

        if combat_just_deactivated?(prev_active: prev_active, combat_context: @adventure.combat_context)
          Battlefield::ArchiveCombatEnd.call(adventure: @adventure)
        end

        snapshot_contexts_to_loop
      end

      def combat_context_evaluator_prompt(what_happened, mutations, allow_combat_initialization:)
        system_prompt = Ai::PromptRenderer.render("combat_context_update",
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
          model: @config.model_for(STEP_NAME),
          meta: { step: STEP_NAME }
        }
      end

      def repair_participant_identities(val, existing:)
        participants = Array(val["participants"])
        return val if participants.empty?

        existing_participants = Array(existing["participants"])
        repaired = participants.map { |p| repair_participant_identity(p, existing_participants) }
        val.merge("participants" => repaired)
      end

      def repair_participant_identity(participant, existing_participants)
        row = participant.is_a?(Hash) ? participant.deep_stringify_keys : {}
        return row unless row["type"].to_s == "npc"

        return row if row["creature_sheet_id"].present?

        repaired_id = existing_participants.find do |existing|
          existing["type"].to_s == "npc" && existing["name"].to_s == row["name"].to_s && existing["creature_sheet_id"].present?
        end&.[]("creature_sheet_id")
        repaired_id ||= @adventure.creature_sheets.unique_id_for_name(row["name"])

        return row.merge("creature_sheet_id" => repaired_id) if repaired_id.present?

        raise Ai::Error, "Combat context update dropped creature_sheet_id for #{row['name'].presence || 'an NPC'}"
      end

      def guard_combat_context_update(val, prev_active:, combat_mutation_state:)
        return val if combat_mutation_state.has_combat_initialization?

        if combat_mutation_state.has_combat_advancement?
          return val if prev_active == true

          @log.play_log!("combat_context_guard", "Ignored combat_state_advancement while combat inactive")
          return nil
        end

        if prev_active != true && val["active"] == true
          @log.play_log!("combat_context_guard", "Ignored synthetic combat activation without combat_initialization")
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
        combat_context.is_a?(Hash) && prev_active == true && combat_context["active"] == false
      end

      def build_canonical_hp
        lines = []
        lines << "Player: #{@sheet.hp}/#{@sheet.max_hp}" if @sheet
        @adventure.creature_sheets.each { |c| lines << "#{c.name}: #{c.hp}/#{c.max_hp}" }
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
