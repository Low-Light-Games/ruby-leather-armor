# frozen_string_literal: true

# Per-user feature toggle.
#
# Each flag has a {mode}: `off` (everyone OFF), `on` (everyone ON), or
# `bucketed` (split by config). A bucketed flag picks one of two
# {bucketing_strategy} values:
#
#   - `granular`: users in `granular_user_ids` are ON; everyone else is OFF.
#   - `modulo`:   users whose `id % modulo_divisor` lands in
#                 `modulo_on_remainders` are ON; everyone else is OFF.
#                 Divisor 2 + on_remainders [1] gives 50/50 odd-on.
#                 Divisor 10 + on_remainders [0] gives a 10% rollout.
#                 Any divisor in 2..10 supports 10–90% in 10% increments.
#
# Granular and modulo are exclusive per flag — pick one. Both lists are
# Postgres integer arrays.
#
# Reads happen on hot pipeline paths; the lookup is a single indexed
# `find_by(key:)` per turn. Add memoization or Rails.cache only if
# measurement shows it's needed.
class FeatureFlag < ApplicationRecord
  MODES = %w[off on bucketed].freeze
  STRATEGIES = %w[granular modulo].freeze
  MODULO_DIVISOR_RANGE = (2..10).freeze

  validates :key, presence: true, uniqueness: true
  validates :mode, inclusion: { in: MODES }
  validates :bucketing_strategy, inclusion: { in: STRATEGIES }, allow_nil: true
  validate :validate_bucketing_config

  scope :ordered, -> { order(:key) }

  def self.enabled_for?(key, user)
    flag = find_by(key: key.to_s)
    return false unless flag

    flag.enabled_for?(user)
  end

  def enabled_for?(user)
    case mode
    when "off"      then false
    when "on"       then true
    when "bucketed" then evaluate_bucket(user)
    else                 false
    end
  end

  private

  def evaluate_bucket(user)
    return false unless user&.id

    case bucketing_strategy
    when "granular" then granular_user_ids.include?(user.id)
    when "modulo"   then evaluate_modulo(user.id)
    else                 false
    end
  end

  def evaluate_modulo(user_id)
    return false if modulo_divisor.blank? || modulo_on_remainders.blank?

    modulo_on_remainders.include?(user_id % modulo_divisor)
  end

  def validate_bucketing_config
    return unless mode == "bucketed"

    if bucketing_strategy.blank?
      errors.add(:bucketing_strategy, "must be set when mode is bucketed")
      return
    end

    validate_modulo_config if bucketing_strategy == "modulo"
  end

  def validate_modulo_config
    unless MODULO_DIVISOR_RANGE.cover?(modulo_divisor.to_i)
      errors.add(:modulo_divisor, "must be between #{MODULO_DIVISOR_RANGE.min} and #{MODULO_DIVISOR_RANGE.max}")
    end

    return if modulo_divisor.blank?

    out_of_range = Array(modulo_on_remainders).reject { |r| (0...modulo_divisor).cover?(r) }
    return if out_of_range.empty?

    errors.add(:modulo_on_remainders, "contains values outside 0..#{modulo_divisor - 1}: #{out_of_range.inspect}")
  end
end
