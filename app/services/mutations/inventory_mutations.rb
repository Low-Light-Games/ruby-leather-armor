# frozen_string_literal: true

module Mutations
  class InventoryMutations
    def initialize(adventure:, sheet:, log:, on_error:)
      @adventure = adventure
      @sheet = sheet
      @log = log
      @on_error = on_error
    end

    def call(inventory_muts)
      return [] unless inventory_muts.present? && @sheet

      adventure_sheet = @adventure.adventure_sheets.first
      return [] unless adventure_sheet

      lines = []
      inventory_muts.each do |item_name, quantity|
        next unless item_name.present? && quantity.is_a?(Numeric) && quantity.to_i > 0

        line = add_item(adventure_sheet, item_name.to_s, quantity.to_i)
        lines << line if line
      end
      lines
    rescue StandardError => e
      @on_error.call("inventory_mutations", e)
    end

    private

    def add_item(adventure_sheet, item_name, quantity)
      item_def = find_or_create_item_definition(item_name)
      return unless item_def

      display_name = item_def.name
      existing = adventure_sheet.adventure_sheet_items.find_by(item_definition_id: item_def.id)
      if existing
        old_quantity = existing.quantity
        new_quantity = old_quantity + quantity
        existing.update!(quantity: new_quantity)
        @log.log!(:info, "Updated inventory: #{item_name} quantity #{old_quantity} -> #{new_quantity}")
        "Updated: #{display_name} — quantity #{old_quantity} → #{new_quantity}"
      else
        adventure_sheet.adventure_sheet_items.create!(
          item_definition_id: item_def.id,
          quantity: quantity,
          equipped: false
        )
        @log.log!(:info, "Added to inventory: #{item_name} (quantity: #{quantity})")
        "Received: #{display_name} ×#{quantity}"
      end
    end

    def find_or_create_item_definition(item_name)
      normalized = item_name.downcase.strip
      ItemDefinition.find_by("LOWER(name) = ?", normalized) ||
        ItemDefinition.where("LOWER(name) LIKE ?", "%#{normalized}%").first ||
        create_generic_item_definition(item_name)
    end

    def create_generic_item_definition(item_name)
      item_id   = item_name.downcase.gsub(/[^a-z0-9]/, "_").gsub(/_+/, "_").gsub(/^_+|_+$/, "")
      counter   = 1
      base_id   = item_id
      item_id   = "#{base_id}_#{counter += 1}" while ItemDefinition.exists?(id: item_id)

      ItemDefinition.create!(
        id: item_id, name: item_name.titleize, item_type: "gear",
        category: nil, slot: "none", weight: 1, cost_gp: 0,
        armor_bonus: 0, shield_bonus: 0, max_dex_bonus: nil,
        armor_check_penalty: 0, arcane_spell_failure: 0,
        speed_30: nil, speed_20: nil, weapon_category: nil,
        weapon_type: nil, damage_dice: nil, critical_range: nil,
        damage_type: nil, range_increment: nil,
        summary: "A generic item acquired during adventure."
      )
    rescue ActiveRecord::RecordInvalid => e
      @log.log!(:error, "Failed to create item definition for '#{item_name}': #{e.message}")
      nil
    end
  end
end
