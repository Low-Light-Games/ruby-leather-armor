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

      # Per commit 15, the AI's combat_context_update output is no
      # longer a full context block — it's a small set of pure deltas
      # the code applies on top of the canonical participant list
      # (which lives in @adventure.combat_context["participants"] and
      # is overwritten by `combat_initialization` / merged by
      # `combat_state_advancement` mutations from CombatGM).
      class Result
        attr_reader :round, :turn_order, :active, :participant_updates

        def self.from_parsed(parsed)
          hash = parsed.is_a?(Hash) ? parsed.deep_stringify_keys : {}
          new(
            unchanged: hash["unchanged"] == true,
            round:      coerce_int(hash["round"]),
            turn_order: Array(hash["turn_order"]).map { |n| n.to_s.strip }.reject(&:empty?),
            active:     coerce_bool(hash["active"]),
            participant_updates: Array(hash["participant_updates"]).filter_map { |u| ParticipantUpdate.parse(u) },
          )
        end

        def self.coerce_int(raw)
          return nil if raw.nil? || raw == ""

          Integer(raw, exception: false)
        end

        def self.coerce_bool(raw)
          return nil if raw.nil?

          return raw if raw == true || raw == false

          nil
        end

        def initialize(unchanged:, round:, turn_order:, active:, participant_updates:)
          @unchanged           = unchanged
          @round               = round
          @turn_order          = turn_order
          @active              = active
          @participant_updates = participant_updates
        end

        def unchanged? = @unchanged

        # The shape changed, so callers that used to ask for `.context`
        # now project participants themselves; this accessor stays as a
        # short escape hatch for tests/logs that want to see whether
        # there was anything substantive to apply.
        def empty?
          @unchanged && @participant_updates.empty? && @round.nil? && @turn_order.empty? && @active.nil?
        end
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

      def combat_context_result(by_step, phase:)
        Result.from_parsed(evaluator_fan_out_result!(by_step, STEP_NAME, phase)["parsed_response"])
      end

      def persist_combat_context(result, mutations)
        prev_combat = @adventure.combat_context.is_a?(Hash) ? @adventure.combat_context.deep_stringify_keys : {}
        prev_active = prev_combat["active"]
        combat_mutation_state = CombatMutationState.new(mutations)
        canonical_combat = combat_mutation_state.canonical_combat_context

        if canonical_combat.blank? && !combat_active_or_pending?(prev_combat) && result.empty?
          return snapshot_contexts_to_loop
        end

        base_context = base_context_for_projection(canonical_combat: canonical_combat, prev_combat: prev_combat)
        return snapshot_contexts_to_loop if base_context.blank?

        validate_participant_identities!(base_context["participants"])

        participants = apply_participant_updates(base_context["participants"], result.participant_updates)
        round        = result.round.presence || base_context["round"]
        turn_order   = result.turn_order.presence || Array(base_context["turn_order"])
        current_turn = (turn_order.first if turn_order.any?) || base_context["current_turn"]
        active       = canonical_or_ai_active(canonical_combat: canonical_combat, base_context: base_context, ai_active: result.active)

        updated = base_context.merge(
          "active"       => active,
          "round"        => round,
          "turn_order"   => turn_order,
          "current_turn" => current_turn,
          "participants" => participants,
        )

        updated = guard_combat_context_update(
          updated, prev_active: prev_active, combat_mutation_state: combat_mutation_state,
        )
        return snapshot_contexts_to_loop if updated.blank?

        @adventure.update!(combat_context: updated)
        @adventure.reload

        if combat_just_deactivated?(prev_active: prev_active, combat_context: @adventure.combat_context)
          Battlefield::ArchiveCombatEnd.call(adventure: @adventure)
        end

        snapshot_contexts_to_loop
      end

      def combat_active_or_pending?(prev_combat)
        prev_combat.is_a?(Hash) && (prev_combat["active"] == true || Array(prev_combat["participants"]).any?)
      end

      def base_context_for_projection(canonical_combat:, prev_combat:)
        if canonical_combat.present?
          canonical_combat.deep_stringify_keys
        else
          prev_combat
        end
      end

      def canonical_or_ai_active(canonical_combat:, base_context:, ai_active:)
        return canonical_combat["active"] if canonical_combat.present? && canonical_combat.key?("active")

        return ai_active if !ai_active.nil?

        base_context["active"]
      end

      # The harden path. Every NPC participant carried in the canonical
      # context (whether from the prior turn or just installed by
      # combat_initialization mutations) MUST resolve to a real
      # creature_sheets row. Anything else is a sign that something
      # upstream invented identity — raise loudly so we see it in
      # Sentry instead of silently corrupting the next turn.
      def validate_participant_identities!(participants)
        Array(participants).each do |raw|
          row = raw.is_a?(Hash) ? raw.deep_stringify_keys : {}
          next unless row["type"].to_s == "npc"

          id = Integer(row["creature_sheet_id"], exception: false)
          unless id&.positive? && @adventure.creature_sheets.exists?(id: id)
            raise Ai::Error, "Combat context carries unknown creature_sheet_id=#{row['creature_sheet_id'].inspect} for #{row['name'].presence || 'an NPC'}"
          end
        end
      end

      def apply_participant_updates(participants, updates)
        roster = Array(participants).map { |p| p.deep_stringify_keys }
        roster_by_id = roster.each_with_object({}) do |participant, h|
          next unless participant["type"].to_s == "npc"

          id = Integer(participant["creature_sheet_id"], exception: false)
          h[id] = participant if id&.positive?
        end

        Array(updates).each do |update|
          participant = roster_by_id[update.creature_sheet_id]
          unless participant
            @log.play_log!(
              "context_update_unknown_id",
              "ContextUpdate: participant_updates references unknown creature_sheet_id=#{update.creature_sheet_id}",
              parsed_response: UnknownIdEvent.new(
                requested_id: update.creature_sheet_id,
                roster_ids:   roster_by_id.keys,
                hp_delta:     update.hp_delta,
                added:        update.conditions_added,
                removed:      update.conditions_removed,
              ).to_h,
            )
            next
          end

          apply_hp_delta!(participant, update.hp_delta)
          apply_condition_delta!(participant, added: update.conditions_added, removed: update.conditions_removed)
        end

        roster
      end

      def apply_hp_delta!(participant, hp_delta)
        return if hp_delta.zero?

        max_hp  = participant["max_hp"].to_i
        current = participant["hp"].to_i
        target  = current + hp_delta
        target  = 0 if target < 0
        target  = max_hp if max_hp.positive? && target > max_hp
        participant["hp"] = target
      end

      def apply_condition_delta!(participant, added:, removed:)
        return if added.empty? && removed.empty?

        current = Array(participant["conditions"]).map(&:to_s)
        participant["conditions"] = ((current - removed) | added).uniq
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
        @adventure.creature_sheets.each { |c| lines << "[id=#{c.id}] #{c.name}: #{c.hp}/#{c.max_hp}" }
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
