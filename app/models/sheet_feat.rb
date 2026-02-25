# frozen_string_literal: true

class SheetFeat < ApplicationRecord
  belongs_to :sheet
  belongs_to :feat_definition, foreign_key: :feat_id

  validates :feat_id, presence: true
  validates :feat_id, uniqueness: { scope: [:sheet_id, :choice],
    message: "already selected with this choice" }
end
