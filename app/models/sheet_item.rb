# frozen_string_literal: true

class SheetItem < ApplicationRecord
  belongs_to :sheet
  belongs_to :item_definition, foreign_key: :item_definition_id

  validates :quantity, numericality: { only_integer: true, greater_than: 0 }

  # Only one item can be equipped per slot (except "none" which is unlimited).
  # Rings use slot_override to distinguish ring_1 / ring_2.
  validate :slot_uniqueness, if: :equipped?

  # The effective slot for this item (uses slot_override if set, otherwise the definition's slot)
  def effective_slot
    slot_override.presence || item_definition&.slot
  end

  private

  def slot_uniqueness
    slot = effective_slot
    return if slot == "none"

    conflict = sheet.sheet_items
                    .where(equipped: true)
                    .where.not(id: id)
                    .select { |si| si.effective_slot == slot }

    if conflict.any?
      errors.add(:base, "Slot '#{slot}' is already occupied")
    end
  end
end
