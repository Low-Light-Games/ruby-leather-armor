# frozen_string_literal: true

module PlayerTurn
  class Messenger
    def initialize(adventure:, log:, user:)
      @adventure = adventure
      @log = log
      @user = user
    end

    def persist_message(role:, content:, message_type:, metadata: {})
      if role != "player" && @log.registry_entry_uuid
        metadata = metadata.merge("registry_entry_uuid" => @log.registry_entry_uuid)
      end
      @adventure.adventure_messages.create!(
        role: role, content: content,
        message_type: message_type, metadata: metadata)
    end

    def messages_for(result)
      case result[:action]
      when :rejected
        if result[:dm_message].present?
          [persist_message(role: "dm", content: result[:dm_message], message_type: "narrative")]
        else
          [persist_message(
            role: "system",
            content: result[:reason] || "Your input was rejected. Please try a valid in-character action.",
            message_type: "sanitization_fail")]
        end

      when :ooc_response
        [persist_message(role: "system", content: result[:response], message_type: "ooc_response")]

      when :battlefield_version_mismatch
        [persist_message(
          role: "system",
          content: result[:message].presence || "Combat map changed since these rolls were requested. Submit again using the updated prompt.",
          message_type: "system_notice")]

      when :awaiting_rolls
        meta = PlayerTurn::Rolls::RollRequestMetadata.build_persist_metadata(result, @adventure)
        msgs = []
        if result[:game_master_narrative].present?
          msgs << persist_message(
            role: "dm",
            content: result[:game_master_narrative],
            message_type: "narrative")
        end
        msgs << persist_message(
          role: "dm",
          content: PlayerTurn::Rolls::RollExplanation.from_summaries(result[:merged][:mechanical_summaries]),
          message_type: "roll_request",
          metadata: meta)
        msgs

      when :awaiting_initiative
        meta = InitiativeRequestMetadata.for_awaiting_initiative(result)
        opener_outcome = meta[:opener_outcome].presence || meta["opener_outcome"].presence
        encounter_intro = AdventureLoop.for_registry_entry(@log.registry_entry_uuid)
                                       .paused.order(:created_at).last
                                       &.get("pipeline_outcome")
        initiative_content = if opener_outcome.present?
                               "Roll for initiative!"
                             else
                               [encounter_intro.presence, "Roll for initiative!"].compact.join("\n\n")
                             end
        msgs = []
        if opener_outcome.present?
          msgs << persist_message(role: "dm", content: opener_outcome, message_type: "action_result")
        end
        msgs << persist_message(
          role: "dm",
          content: initiative_content,
          message_type: "initiative_request",
          metadata: meta)
        msgs

      when :combat_initialized
        msgs = []
        if result[:combat_start_message].present?
          msgs << persist_message(
            role: "dm",
            content: result[:combat_start_message],
            message_type: "narrative")
        end
        msgs.concat(persist_combat_log_messages(result[:world_turn_lines]))
        msgs.concat(persist_event_messages(result))
        msgs

      when :narrated
        msgs = []
        msgs.concat(persist_action_result_messages(result[:action_outcomes]))
        msgs.concat(persist_combat_log_messages(result[:world_turn_lines]))
        msgs << persist_message(role: "dm", content: result[:narrative], message_type: "narrative")
        msgs.concat(persist_event_messages(result))

      when :narrated_sequence
        signal_done_to_the_frontend
      end
    end

    def handle_progressive_narrative(narrative_entry)
      msg = persist_message(
        role: "dm",
        content: narrative_entry[:narrative],
        message_type: "narrative",
        metadata: ProgressiveNarrativeMetadata.for_entry(narrative_entry)
      )

      admin = @user&.admin?
      to_broadcast = [Adventures::MessageSerializer.as_json(msg, admin: admin)]

      persist_event_messages(narrative_entry).each do |event_msg|
        to_broadcast << Adventures::MessageSerializer.as_json(event_msg, admin: admin)
      end

      AdventureChannel.broadcast_to(@adventure, { type: "pipeline_action_result", messages: to_broadcast })
    end

    def usage_limit_rejection_messages(error)
      [persist_message(role: "system", content: error.message, message_type: "usage_limit")]
    end

    def sanitization_failure_messages(error)
      @log.error_registry_entry!
      [persist_message(role: "system", content: error.message, message_type: "sanitization_fail")]
    end

    def pipeline_exception_messages(error)
      @log.capture_pipeline_exception!(error)
      @log.error_registry_entry!(error)
      [persist_message(
        role: "system",
        content: "The Dungeon Master is momentarily distracted... (#{player_facing_error(error)})",
        message_type: "narrative")]
    end

    private

    def persist_action_result_messages(outcomes)
      Array(outcomes).filter_map do |outcome|
        next if outcome.blank?

        persist_message(role: "dm", content: outcome, message_type: "action_result")
      end
    end

    def persist_combat_log_messages(lines)
      Array(lines).filter_map do |line|
        next if line.blank?

        persist_message(role: "dm", content: line, message_type: "combat_log")
      end
    end

    def persist_event_messages(entry)
      msgs = []
      if entry[:adventure_complete]
        @adventure.mark_ended!(reason: "adventure_complete")
        msgs << persist_message(
          role: "system",
          content: "The adventure has reached its conclusion.",
          message_type: "adventure_complete")
      end
      if entry[:player_death]
        msgs.concat(combat_bookend_messages("player_death"))
        @adventure.mark_ended!(reason: "player_death")
        msgs << persist_message(
          role: "system",
          content: "Your character has died.",
          message_type: "player_death")
      end
      if entry[:player_incapacitated]
        msgs << persist_message(
          role: "system",
          content: "Your character is unconscious and dying. Without aid, death follows.",
          message_type: "player_incapacitated")
      end
      if !entry[:player_death] && !entry[:player_incapacitated] && combat_just_ended?(entry)
        msgs.concat(combat_bookend_messages("all_npcs_defeated"))
      end
      msgs
    end

    def combat_just_ended?(entry)
      entry[:combat_ended] || entry["combat_ended"]
    end

    def combat_bookend_messages(reason)
      narration = Combat::BookendNarration.new(
        adventure: @adventure, config: DmConfig.instance, log: @log
      ).narrate_combat_end(reason: reason)
      return [] if narration.blank?

      [persist_message(role: "dm", content: narration, message_type: "combat_end")]
    end

    def signal_done_to_the_frontend
      []
    end

    def player_facing_error(error)
      case error
      when Ai::TokenBudgetExceededError
        "Could not reach the AI service. Please try again shortly."
      else
        error.message
      end
    end
  end
end
