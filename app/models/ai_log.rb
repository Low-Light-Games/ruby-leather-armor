class AiLog < ApplicationRecord
  belongs_to :adventure

  validates :call_type, presence: true, inclusion: { in: %w[sanitization dm_response roll_response] }
  validates :prompt_summary, presence: true
  validates :status, presence: true, inclusion: { in: %w[success parse_fallback parse_error api_error] }

  scope :recent_first, -> { order(created_at: :desc) }
end
