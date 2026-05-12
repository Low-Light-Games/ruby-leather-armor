# frozen_string_literal: true

module Coerce
  def self.actor_sheet_id(raw)
    return nil if raw.nil? || raw == ""

    id = Integer(raw, exception: false)
    id&.positive? ? id : nil
  end
end
