# frozen_string_literal: true

module DungeonMaster
  module Presenters
    # Prompt-safe text for the player's {AdventureSheet} (PC stat block for LLM prompts).
    class AdventureSheetPromptPresenter
      include CharacterPromptFormatting

      SOCIAL_SKILLS = %w[
        Bluff Diplomacy Disguise Handle\ Animal Intimidate
        Knowledge\ (Local) Knowledge\ (Nobility) Linguistics
        Perception Perform Sense\ Motive Use\ Magic\ Device
      ].freeze

      TRAVERSAL_SKILLS = %w[
        Acrobatics Climb Fly Knowledge\ (Geography) Knowledge\ (Nature)
        Perception Ride Stealth Survival Swim
      ].freeze

      COMBAT_ITEM_TYPES = %w[weapon armor shield potion ammunition].freeze

      def initialize(sheet)
        @sheet = sheet
      end

      def identity
        "#{@sheet.name} — #{@sheet.race} #{@sheet.character_class} #{@sheet.level}"
      end

      def for_category(category)
        case category
        when "combat"    then combat_text
        when "social"    then social_text
        when "traversal" then traversal_text
        else                  full_text
        end
      end

      def full_text
        compose([
          *base_parts,
          ability_scores_line,
          hp_currency_line,
          derived_combat_block,
          skills_block,
          feats_block,
          spells_block,
          items_block
        ])
      end

      def combat_text
        compose([
          *base_parts,
          ability_scores_line,
          hp_currency_line,
          derived_combat_block,
          feats_block(categories: %w[combat general]),
          spells_block,
          items_block(types: COMBAT_ITEM_TYPES, equipped_only: true)
        ])
      end

      def social_text
        compose([
          *base_parts,
          "CHA: #{@sheet.charisma}, WIS: #{@sheet.wisdom}, INT: #{@sheet.intelligence}  |  Level: #{@sheet.level}",
          skills_block(filter: SOCIAL_SKILLS),
          feats_block,
          items_block(types: %w[wondrous], equipped_only: true)
        ])
      end

      def traversal_text
        compose([
          *base_parts,
          "STR: #{@sheet.strength}, DEX: #{@sheet.dexterity}, CON: #{@sheet.constitution}, WIS: #{@sheet.wisdom}  |  Level: #{@sheet.level}",
          traversal_movement_line,
          skills_block(filter: TRAVERSAL_SKILLS),
          feats_block,
          items_block
        ])
      end

      alias full full_text
      alias combat combat_text
      alias social social_text
      alias traversal traversal_text

      private

      def base_parts
        [identity, conditions_line]
      end

      def compose(parts)
        parts.reject(&:blank?).join("\n")
      end

      def derived_stats
        @derived_stats ||= @sheet.derived_stats
      end

      def hp_currency_line
        "HP: #{@sheet.hp}/#{@sheet.max_hp}  |  Currency: #{format_currency(@sheet.currency)}"
      end

      def traversal_movement_line
        ds = derived_stats
        "Speed: #{ds['speed'] || 30} ft  |  Encumbrance: #{ds['encumbrance'] || 'light'}  |  Carry: #{format_carry(ds)}"
      end

      def conditions_line
        conds = Array(@sheet.try(:conditions))
        return nil if conds.empty?
        "Active Conditions: #{conds.join(', ')}"
      end

      def ability_scores_line
        "STR: #{@sheet.strength}, DEX: #{@sheet.dexterity}, CON: #{@sheet.constitution}, " \
          "INT: #{@sheet.intelligence}, WIS: #{@sheet.wisdom}, CHA: #{@sheet.charisma}"
      end

      def derived_combat_block
        ds = derived_stats
        return "" if ds.blank?

        <<~STATS.strip
          BAB: +#{ds['bab']}  |  AC: #{ds['ac']} (Touch #{ds['touch_ac']}, Flat-Footed #{ds['flat_footed_ac']})
          Fort: #{format_mod(ds['fort'])}  Ref: #{format_mod(ds['ref'])}  Will: #{format_mod(ds['will'])}
          CMB: #{format_mod(ds['cmb'])}  CMD: #{ds['cmd']}  Initiative: #{format_mod(ds['initiative'])}
          Melee: #{format_mod(ds['melee_attack'])}  Ranged: #{format_mod(ds['ranged_attack'])}
          Speed: #{ds['speed']} ft  Size: #{ds['size']}
        STATS
      end

      def skills_block(filter: nil)
        ds = derived_stats
        return "" if ds.blank? || ds["skills"].blank?

        skills = ds["skills"]
        skills = skills.select { |s| filter.include?(s["name"]) } if filter
        return "" if skills.empty?

        "Skills: " + skills.map { |s| "#{s['name']} #{format_mod(s['total'])}" }.join(", ")
      end

      def feats_block(categories: nil)
        feats = @sheet.adventure_sheet_feats.includes(:feat_definition).to_a
        feats = feats.select { |f| f.feat_definition && categories.include?(f.feat_definition.category) } if categories
        return "" if feats.empty?

        lines = feats.filter_map do |f|
          fd = f.feat_definition
          next unless fd
          f.choice.present? ? "#{fd.name} (#{f.choice})" : fd.name
        end

        "Feats: #{lines.join(', ')}"
      end

      def spells_block
        spells = @sheet.adventure_sheet_spells.includes(:spell_definition).to_a
        return "" if spells.empty?

        lines = spells.filter_map { |s| s.spell_definition&.name }
        "Spells:\n" + lines.map { |name| "  - #{name}" }.join("\n")
      end

      def items_block(types: nil, equipped_only: false)
        items = @sheet.adventure_sheet_items.includes(:item_definition).to_a
        items = items.select(&:equipped?) if equipped_only
        items = items.select { |i| i.item_definition && types.include?(i.item_definition.item_type) } if types
        return "" if items.empty?

        lines = items.filter_map do |i|
          next unless i.item_definition
          line = i.item_definition.name
          line += " (x#{i.quantity})" if i.quantity && i.quantity > 1
          line += " [equipped]" if i.equipped?
          line
        end

        "Items: #{lines.join(', ')}"
      end
    end
  end
end
