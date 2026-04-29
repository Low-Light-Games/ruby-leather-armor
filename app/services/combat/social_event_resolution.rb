# frozen_string_literal: true

module Combat
  # PlayLog payload describing a combat action that crossed the social
  # threshold (a hostile act in front of NPCs). Persisted under
  # event_type 'social_event_triggered' for the next pipeline pass to
  # read.
  class SocialEventResolution
    KIND = 'social_event_triggered'

    # @param action_kind [String]
    # @param action_label [String, nil]
    # @param target_name [String, nil]
    # @param witnesses [Array<Hash>]
    # @param location [String, nil]
    def initialize(action_kind:, action_label:, target_name:, witnesses:, location:)
      @action_kind = action_kind
      @action_label = action_label
      @target_name = target_name
      @witnesses = witnesses
      @location = location
    end

    def to_h
      {
        'kind' => KIND,
        'action_kind' => @action_kind,
        'action_label' => @action_label,
        'target_name' => @target_name,
        'witnesses' => @witnesses,
        'location' => @location,
        'at' => Time.current.iso8601
      }
    end
  end
end
