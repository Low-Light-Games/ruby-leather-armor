# frozen_string_literal: true

class AdventureSheetFeat < ApplicationRecord
  belongs_to :adventure_sheet
  belongs_to :feat_definition, foreign_key: :feat_id

  validates :feat_id, presence: true
  validates :pool, presence: true
  validates :feat_id, uniqueness: { scope: [:adventure_sheet_id, :choice],
    message: "already selected with this choice" }
end
