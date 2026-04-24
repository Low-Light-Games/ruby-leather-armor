# frozen_string_literal: true

module Adventures
  # Copies a player Sheet into an AdventureSheet for a given adventure,
  # including feat, spell, and item pivot records. Class abilities are not copied;
  # they are resolved live from class/level via {SheetClassAbilities}.
  class SheetCopier
    def initialize(adventure, sheet, max_hp:, currency:)
      @adventure = adventure
      @sheet     = sheet
      @max_hp    = max_hp
      @currency  = currency
    end

    def call
      adv_sheet = @adventure.adventure_sheets.create!(adventure_sheet_attrs_with_skill_ranks)
      copy_feats(adv_sheet)
      copy_spells(adv_sheet)
      copy_items(adv_sheet)
      adv_sheet.recompute_derived_stats!
      adv_sheet
    end

    private

    def adventure_sheet_attrs_with_skill_ranks
      attrs = adventure_sheet_attributes
      merge_skill_ranks!(attrs) if AdventureSheet.column_names.include?('skill_ranks')
      attrs
    end

    def merge_skill_ranks!(attrs)
      attrs[:skill_ranks] = if Sheet.column_names.include?('skill_ranks')
                              (@sheet.skill_ranks || {}).deep_dup
                            else
                              {}
                            end
    end

    def adventure_sheet_attributes
      sheet_link_and_name
        .merge(ability_scores_hash)
        .merge(class_and_level)
        .merge(adventure_sheet_payload)
    end

    def sheet_link_and_name
      {
        sheet: @sheet,
        name: @sheet.name,
        description: @sheet.description
      }
    end

    def ability_scores_hash
      {
        strength: @sheet.strength,
        intelligence: @sheet.intelligence,
        dexterity: @sheet.dexterity,
        constitution: @sheet.constitution,
        wisdom: @sheet.wisdom,
        charisma: @sheet.charisma
      }
    end

    def class_and_level
      {
        race: @sheet.race,
        racial_bonus_attribute: @sheet.racial_bonus_attribute,
        character_class: @sheet.character_class,
        subclass: @sheet.subclass,
        level: @sheet.level
      }
    end

    def adventure_sheet_payload
      {
        details: (@sheet.details || {}).deep_dup,
        currency: @currency,
        hp: @max_hp,
        max_hp: @max_hp,
        items: nil,
        effects: nil
      }
    end

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
          quantity: si.quantity,
          equipped: si.equipped,
          slot_override: si.slot_override
        )
      end
    end
  end
end
