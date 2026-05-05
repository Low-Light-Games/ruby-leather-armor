# frozen_string_literal: true

# Persisted chat-history row for one adventure: player input, DM
# narration, system notices, and per-step events (combat log, roll
# requests/results, etc.). The frontend AdventureChannel renders
# entries by message_type; new types must be allow-listed here.
class AdventureMessage < ApplicationRecord
  belongs_to :adventure

  validates :role, presence: true, inclusion: { in: %w[player dm system] }
  validates :content, presence: true
  validates :message_type, presence: true, inclusion: {
    in: %w[narrative sanitization_fail adventure_complete player_death player_incapacitated roll_request roll_result
           initiative_request initiative_result dm_query moderation_flagged usage_limit system_notice
           combat_log combat_end action_result]
  }

  scope :chronological, -> { order(created_at: :asc) }
  scope :newest_first, -> { order(created_at: :desc) }
  scope :from_players, -> { where(role: 'player') }
  scope :for_message_types, ->(types) { where(message_type: types) }
  # The narrative prose the player actually reads as DM speech: per-turn
  # narration plus per-action resolution lines. Excludes meta rows
  # (roll_request, roll_result, system_notice, combat_log, dm_query) so
  # callers reaching for "what happened lately, in DM-voice" get a clean
  # slice without filtering each consumer-side.
  scope :dm_narration, -> { where(message_type: %w[narrative action_result]) }
end
