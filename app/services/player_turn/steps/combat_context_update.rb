# frozen_string_literal: true

module PlayerTurn
  module Steps
    module CombatContextUpdate
      STEP_NAME = "combat_context_update"

      class CombatMutationState
        def initialize(mutations)
          @mutations = mutations.is_a?(Hash) ? mutations.deep_stringify_keys : {}
        end

        def canonical_combat_context
          @mutations["combat_initialization"] || @mutations["combat_state_advancement"]
        end
      end

      class CombatContextChangeSet
        attr_reader :round, :turn_order, :active, :participant_updates

        def self.empty
          new(round: nil, turn_order: [], active: nil, participant_updates: [])
        end

        def self.from_parsed(parsed)
          hash = parsed.is_a?(Hash) ? parsed.deep_stringify_keys : {}
          new(
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

        def initialize(round:, turn_order:, active:, participant_updates:)
          @round               = round
          @turn_order          = turn_order
          @active              = active
          @participant_updates = participant_updates
        end

        def empty?
          @participant_updates.empty? && @round.nil? && @turn_order.empty? && @active.nil?
        end
      end

      private

      def run_context_updates(what_happened, mutations)
        canonical = CombatMutationState.new(mutations).canonical_combat_context

        if combat_active?
          delta = fetch_ai_combat_context_delta(what_happened, mutations, phase: "context_update")
          persist_combat_context(delta, mutations)
        elsif canonical.present?
          persist_combat_context(CombatContextChangeSet.empty, mutations)
        else
          snapshot_contexts_to_loop
        end
      rescue => e
        pipeline_error!("context_updates", e)
      end

      def fetch_ai_combat_context_delta(what_happened, mutations, phase:)
        broadcast_progress("Remembering the world...")
        prompts = [combat_context_evaluator_prompt(what_happened, mutations)]
        by_step = evaluator_fan_out!(prompts, what_happened, phase: phase)
        CombatContextChangeSet.from_parsed(evaluator_fan_out_result!(by_step, STEP_NAME, phase)["parsed_response"])
      end

      def persist_combat_context(delta, mutations)
        prev_combat = @adventure.combat_context.is_a?(Hash) ? @adventure.combat_context.deep_stringify_keys : {}
        prev_active = prev_combat["active"]
        canonical = CombatMutationState.new(mutations).canonical_combat_context

        return snapshot_contexts_to_loop if canonical.blank? && !combat_active_or_pending?(prev_combat) && delta.empty?

        base_context = canonical.present? ? canonical.deep_stringify_keys : prev_combat
        return snapshot_contexts_to_loop if base_context.blank?

        validate_participant_identities!(base_context["participants"])

        participants = apply_participant_updates(base_context["participants"], delta.participant_updates)
        turn_state   = project_turn_state(canonical: canonical, base_context: base_context, delta: delta)
        active       = project_active_flag(canonical: canonical, base_context: base_context, ai_active: delta.active)

        updated = base_context.merge(
          "active"       => active,
          "round"        => turn_state[:round],
          "turn_order"   => turn_state[:turn_order],
          "current_turn" => turn_state[:current_turn],
          "participants" => participants,
        )

        @adventure.update!(combat_context: updated)
        @adventure.reload

        if combat_just_deactivated?(prev_active: prev_active, combat_context: @adventure.combat_context)
          Battlefield::ArchiveCombatEnd.call(adventure: @adventure)
        end

        snapshot_contexts_to_loop
      end

      def project_turn_state(canonical:, base_context:, delta:)
        if canonical.present?
          return {
            round: base_context["round"],
            turn_order: Array(base_context["turn_order"]),
            current_turn: base_context["current_turn"]
          }
        end

        turn_order = delta.turn_order.presence || Array(base_context["turn_order"])
        current_turn = delta.turn_order.presence ? turn_order.first : base_context["current_turn"]
        {
          round: delta.round.presence || base_context["round"],
          turn_order: turn_order,
          current_turn: current_turn
        }
      end

      def project_active_flag(canonical:, base_context:, ai_active:)
        return canonical["active"] if canonical.present? && canonical.key?("active")

        return ai_active unless ai_active.nil?

        base_context["active"]
      end

      def combat_active_or_pending?(prev_combat)
        prev_combat.is_a?(Hash) && (prev_combat["active"] == true || Array(prev_combat["participants"]).any?)
      end

      # @raise [Ai::Error] when any NPC participant has no live `adventure_actor_sheets` row
      def validate_participant_identities!(participants)
        Array(participants).each do |raw|
          row = raw.is_a?(Hash) ? raw.deep_stringify_keys : {}
          next unless row["type"].to_s == "npc"

          id = Integer(row["actor_sheet_id"], exception: false)
          unless id&.positive? && @adventure.adventure_actor_sheets.exists?(id: id)
            raise Ai::Error, "Combat context carries unknown actor_sheet_id=#{row['actor_sheet_id'].inspect} for #{row['name'].presence || 'an NPC'}"
          end
        end
      end

      def apply_participant_updates(participants, updates)
        roster = Array(participants).map { |p| p.deep_stringify_keys }
        roster_by_id = roster.each_with_object({}) do |participant, h|
          next unless participant["type"].to_s == "npc"

          id = Integer(participant["actor_sheet_id"], exception: false)
          h[id] = participant if id&.positive?
        end

        Array(updates).each do |update|
          participant = roster_by_id[update.actor_sheet_id]
          unless participant
            @log.play_log!(
              "context_update_unknown_id",
              "ContextUpdate: participant_updates references unknown actor_sheet_id=#{update.actor_sheet_id}",
              parsed_response: UnknownIdEvent.new(
                requested_id: update.actor_sheet_id,
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

      def combat_context_evaluator_prompt(what_happened, mutations)
        system_prompt = Ai::PromptRenderer.render("combat_context_update",
          current_context: @adventure.combat_context,
          context_schema: Ai::PromptRenderer.load_schema("contexts/combat_context"),
          what_happened: what_happened,
          mutations_json: mutations.present? ? mutations.to_json : nil,
          canonical_hp: build_canonical_hp,
          canonical_participants: canonical_combat_participants)

        {
          system_prompt:    system_prompt,
          user_message:     what_happened,
          model:            @config.model_for(STEP_NAME),
          reasoning_effort: @config.reasoning_effort_for(STEP_NAME),
          meta:             { step: STEP_NAME }
        }
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
        @adventure.adventure_actor_sheets.each { |c| lines << "[id=#{c.id}] #{c.name}: #{c.hp}/#{c.max_hp}" }
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
