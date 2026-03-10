# frozen_string_literal: true

module Adventures
  # Copies a player Sheet into an AdventureSheet for a given adventure,
  # including all feat, spell, and item pivot records.
  class SheetCopier
    def initialize(adventure, sheet, max_hp:, currency:)
      @adventure = adventure
      @sheet     = sheet
      @max_hp    = max_hp
      @currency  = currency
    end

    def call
      adv_sheet = @adventure.adventure_sheets.create!(
        sheet:                  @sheet,
        name:                   @sheet.name,
        description:            @sheet.description,
        strength:               @sheet.strength,
        intelligence:           @sheet.intelligence,
        dexterity:              @sheet.dexterity,
        constitution:           @sheet.constitution,
        wisdom:                 @sheet.wisdom,
        charisma:               @sheet.charisma,
        race:                   @sheet.race,
        racial_bonus_attribute: @sheet.racial_bonus_attribute,
        character_class:        @sheet.character_class,
        subclass:               @sheet.subclass,
        level:                  @sheet.level,
        details:                (@sheet.details || {}).deep_dup,
        currency:               @currency,
        hp:                     @max_hp,
        max_hp:                 @max_hp,
        items:                  nil,
        effects:                nil
      )

      copy_feats(adv_sheet)
      copy_spells(adv_sheet)
      copy_items(adv_sheet)

      adv_sheet.recompute_derived_stats!
      adv_sheet
    end

    private

    def copy_feats(adv_sheet)
      @sheet.sheet_feats.each do |sf|
        adv_sheet.adventure_sheet_feats.create!(feat_id: sf.feat_id, choice: sf.choice)
      end
    end

    def copy_spells(adv_sheet)
      @sheet.sheet_spells.each do |ss|
        adv_sheet.adventure_sheet_spells.create!(spell_id: ss.spell_id, storage_type: ss.storage_type)
      end
    end

    def copy_items(adv_sheet)
      @sheet.sheet_items.each do |si|
        adv_sheet.adventure_sheet_items.create!(
          item_definition_id: si.item_definition_id,
          quantity:           si.quantity,
          equipped:           si.equipped,
          slot_override:      si.slot_override
        )
      end
    end
  end
end
