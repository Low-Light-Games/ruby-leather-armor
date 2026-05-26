# frozen_string_literal: true

# Persisted chat-history row for one adventure: player input, DM
# narration, system notices, and per-step events (combat log, roll
# requests/results, etc.). The frontend AdventureChannel renders
# entries by message_type; new types must be allow-listed here.
class AdventureMessage < ApplicationRecord
  belongs_to :adventure
  belongs_to :user, optional: true

  validates :role, presence: true, inclusion: { in: %w[player dm system] }
  validates :content, presence: true
  validates :message_type, presence: true, inclusion: {
    in: %w[narrative sanitization_fail adventure_complete player_death player_incapacitated roll_request roll_result
           initiative_request initiative_result moderation_flagged usage_limit system_notice
           combat_log combat_end action_result ooc_response]
  }

  scope :chronological, -> { order(created_at: :asc) }
  scope :newest_first, -> { order(created_at: :desc) }
  scope :from_players, -> { where(role: 'player') }
  scope :for_message_types, ->(types) { where(message_type: types) }
  scope :dm_narration, -> { where(message_type: %w[narrative action_result]) }
  scope :combat_activity, -> { where(message_type: %w[combat_log action_result narrative]) }

  # Accepts a Time, DateTime, or ISO8601 string; returns the full scope when given nil/blank.
  scope :created_since, ->(time) {
    parsed = time.is_a?(String) ? Time.zone.parse(time) : time
    parsed ? where("created_at >= ?", parsed) : all
  }

  def self.player_stats_by_user_id
    from_players
      .where.not(user_id: nil)
      .group(:user_id)
      .pluck(:user_id, Arel.sql('MAX(created_at)'), Arel.sql('COUNT(*)'))
      .each_with_object({}) do |(user_id, last_at, count), memo|
        memo[user_id] = { last_at: last_at, count: count }
      end
  end
end
