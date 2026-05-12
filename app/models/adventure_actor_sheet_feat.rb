# frozen_string_literal: true

class AdventureActorSheetFeat < ApplicationRecord
  belongs_to :adventure_actor_sheet, foreign_key: :actor_sheet_id, inverse_of: :adventure_actor_sheet_feats
  belongs_to :feat_definition, foreign_key: :feat_id

  validates :feat_id, presence: true
  validates :feat_id, uniqueness: { scope: [:actor_sheet_id, :choice],
    message: "already selected with this choice" }
end
