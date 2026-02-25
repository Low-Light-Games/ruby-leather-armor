# frozen_string_literal: true

class SheetSpell < ApplicationRecord
  belongs_to :sheet
  belongs_to :spell_definition, foreign_key: :spell_id

  validates :spell_id, presence: true
  validates :storage_type, presence: true, inclusion: { in: %w[known spellbook] }
  validates :spell_id, uniqueness: { scope: [:sheet_id, :storage_type],
    message: "already in this storage" }
end
