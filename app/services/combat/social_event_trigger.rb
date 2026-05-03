# frozen_string_literal: true

module Combat
  # PR-H of the combat-determinism arc — see docs/combat_redesign.md.
  #
  # Pure heuristic over a deterministic combat action_event. Returns a
  # trigger payload when the action has plausible social ramifications
  # — drawing steel in a tavern, casting a spell with NPCs watching,
  # dropping an enemy in front of an audience — otherwise nil. The AI
  # never runs here; this is the gate.
  #
  # Triggered events get logged as `social_event_triggered` rows that
  # downstream context-update / chronicler passes can read on the next
  # pipeline run. ContextUpdate stays the sole writer of social_context
  # (per the existing invariant in
  # app/services/dungeon_master/steps/context_update.rb).
  module SocialEventTrigger
    SENSITIVE_ATTACK_KINDS = %w[attack].freeze

    module_function

    # @param adventure [Adventure]
    # @param action_event [Hash] payload from PlayerActionResolver#log_action_event!
    # @return [Hash, nil]
    def evaluate(adventure, action_event)
      return nil unless action_event.is_a?(Hash)

      payload = action_event.deep_stringify_keys
      kind = payload['kind'].to_s
      return nil unless SENSITIVE_ATTACK_KINDS.include?(kind)

      witnesses = social_witnesses_for(adventure)
      return nil if witnesses.empty?

      Combat::SocialEventResolution.new(
        action_kind: kind,
        action_label: payload['attack_label'] || payload['message'],
        target_name: payload['target_name'],
        witnesses: witnesses,
        location: location_label_for(adventure)
      ).to_h
    end

    def social_witnesses_for(adventure)
      current_location_name = adventure&.current_location&.name
      return [] if current_location_name.blank?

      AdventureNpc.for_adventure(adventure)
                  .at_location(current_location_name)
                  .non_hostile
                  .pluck(:name, :attitude)
                  .map { |name, attitude| { 'name' => name, 'attitude' => attitude } }
    end

    def location_label_for(adventure)
      adventure&.current_location&.name
    end

    def maybe_log!(adventure, action_event, log: nil)
      payload = evaluate(adventure, action_event)
      return nil unless payload

      record_via(log, adventure, payload) || record_directly(adventure, payload)
      payload
    end

    def record_via(log, _adventure, payload)
      return false unless log.respond_to?(:play_log!)

      log.play_log!('social_event_triggered',
                    "Combat action with social weight: #{payload['action_label']}",
                    parsed_response: payload)
      true
    rescue StandardError => e
      Rails.logger.warn("[SocialEventTrigger] play_log via Logging failed: #{e.message}")
      false
    end

    def record_directly(adventure, payload)
      PlayLog.create!(
        adventure: adventure,
        event_type: 'social_event_triggered',
        prompt_summary: "Combat action with social weight: #{payload['action_label']}".truncate(200),
        parsed_response: payload.to_json,
        status: 'pipeline_event',
        app_version: defined?(APP_VERSION) ? APP_VERSION : nil
      )
    rescue StandardError => e
      Rails.logger.warn("[SocialEventTrigger] play_log direct create failed: #{e.message}")
    end
  end
end
