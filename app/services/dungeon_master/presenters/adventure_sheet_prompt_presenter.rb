# frozen_string_literal: true

module DungeonMaster
  module Presenters
    # Prompt-safe text for the player's {AdventureSheet} (PC stat block for LLM prompts).
    class AdventureSheetPromptPresenter
      include CharacterPromptFormatting

      def initialize(sheet)
        @sheet = sheet
      end

      def identity
        "#{@sheet.name} — #{@sheet.race} #{@sheet.character_class} #{@sheet.level}"
      end

      def full_text
        compose([
          *base_parts,
          ability_scores_line,
          hp_currency_line,
          derived_combat_block,
          skills_block,
          class_abilities_block,
          feats_block,
          spells_block,
          items_block
        ])
      end

      alias full full_text

      private

      def base_parts
        [identity, conditions_line, active_buffs_line]
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

      def conditions_line
        conds = CharacterStats::PersistedJsonArray.list(@sheet.try(:conditions))
        return nil if conds.empty?

        "Active Conditions: #{conds.join(', ')}"
      end

      def active_buffs_line
        buffs = CharacterStats::PersistedJsonArray.list(@sheet.try(:active_buffs))
        return nil if buffs.empty?

        ctx = @sheet.try(:adventure)&.time_context || {}
        current_hours = (ctx["adventure_day"].to_i - 1) * 24.0 + ctx["current_hour"].to_f

        parts = buffs.map do |b|
          st = b["source_type"].presence
          label = b["source"].to_s
          label += " [#{st}]" if st
          label += " (#{b['bonus_type']} #{format_mod(b['value'].to_i)} → #{b['target']})"
          if b["expires_at_game_hours"]
            remaining_h = b["expires_at_game_hours"].to_f - current_hours
            remaining_min = (remaining_h * 60).round
            label += " [~#{remaining_min}m remaining]"
          else
            label += " [sustained]"
          end
          label
        end

        "Active Buffs: #{parts.join('; ')}"
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

      def class_abilities_block
        abilities = @sheet.class_ability_definitions.to_a
        return "" if abilities.empty?

        lines = abilities.map { |a| "#{a.name} (#{a.id})" }
        "Class Abilities: #{lines.join(', ')}"
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
