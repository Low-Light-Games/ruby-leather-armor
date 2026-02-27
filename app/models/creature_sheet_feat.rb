# frozen_string_literal: true

class CreatureSheetFeat < ApplicationRecord
  belongs_to :creature_sheet
  belongs_to :feat_definition, foreign_key: :feat_id

  validates :feat_id, presence: true
  validates :feat_id, uniqueness: { scope: [:creature_sheet_id, :choice],
    message: "already selected with this choice" }
end
