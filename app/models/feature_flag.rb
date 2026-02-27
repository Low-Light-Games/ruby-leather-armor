# frozen_string_literal: true

class FeatureFlag < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  def self.enabled?(key)
    flag = find_by(key: key.to_s)
    flag&.enabled? || false
  end
end
