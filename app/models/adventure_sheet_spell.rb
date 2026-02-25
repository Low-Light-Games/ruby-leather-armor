# frozen_string_literal: true

class AdventureSheetSpell < ApplicationRecord
  belongs_to :adventure_sheet
  belongs_to :spell_definition, foreign_key: :spell_id

  validates :spell_id, presence: true
  validates :storage_type, presence: true, inclusion: { in: %w[known spellbook] }
  validates :spell_id, uniqueness: { scope: [:adventure_sheet_id, :storage_type],
    message: "already in this storage" }
end
