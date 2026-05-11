# frozen_string_literal: true

class AdventureActorSheetSpell < ApplicationRecord
  belongs_to :adventure_actor_sheet, foreign_key: :actor_sheet_id, inverse_of: :adventure_actor_sheet_spells
  belongs_to :spell_definition, foreign_key: :spell_id

  validates :spell_id, presence: true
  validates :storage_type, presence: true, inclusion: { in: %w[known spellbook] }
  validates :spell_id, uniqueness: { scope: [:actor_sheet_id, :storage_type],
    message: "already in this storage" }
end
