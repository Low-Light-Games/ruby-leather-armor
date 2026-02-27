# frozen_string_literal: true

class CreatureSheetSpell < ApplicationRecord
  belongs_to :creature_sheet
  belongs_to :spell_definition, foreign_key: :spell_id

  validates :spell_id, presence: true
  validates :storage_type, presence: true, inclusion: { in: %w[known spellbook] }
  validates :spell_id, uniqueness: { scope: [:creature_sheet_id, :storage_type],
    message: "already in this storage" }
end
