# frozen_string_literal: true

class CreatureSheetItem < ApplicationRecord
  belongs_to :creature_sheet
  belongs_to :item_definition, foreign_key: :item_definition_id

  validates :quantity, numericality: { only_integer: true, greater_than: 0 }

  validate :slot_uniqueness, if: :equipped?

  def effective_slot
    slot_override.presence || item_definition&.slot
  end

  private

  def slot_uniqueness
    slot = effective_slot
    return if slot == "none"

    conflict = creature_sheet.creature_sheet_items
                             .where(equipped: true)
                             .where.not(id: id)
                             .select { |si| si.effective_slot == slot }

    if conflict.any?
      errors.add(:base, "Slot '#{slot}' is already occupied")
    end
  end
end
