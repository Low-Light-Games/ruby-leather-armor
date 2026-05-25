# frozen_string_literal: true

module Adventures
  class RecentMessages
    def self.conversation(adventure, limit: 3)
      adventure.adventure_messages
        .where(role: %w[player dm], message_type: %w[narrative action_result ooc_response])
        .order(created_at: :desc)
        .limit(limit)
        .pluck(:role, :content)
        .reverse
    end

    def self.dm_narration(adventure, limit: 5)
      adventure.adventure_messages
        .where(role: "dm", message_type: %w[narrative action_result])
        .order(created_at: :desc)
        .limit(limit)
        .pluck(:content)
        .reverse
    end

    def self.combat_activity(adventure, limit: 20)
      adventure.adventure_messages
        .combat_activity
        .newest_first
        .limit(limit)
        .pluck(:content)
        .reverse
    end
  end
end
