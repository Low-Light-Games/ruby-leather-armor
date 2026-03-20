# frozen_string_literal: true

module DungeonMaster
  # Builds text representations of player and creature stat blocks for
  # inclusion in AI prompts. Each variant (combat, social, traversal, full)
  # includes only the information relevant to that context.
  module CharacterBlock
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

    def self.load_sheet(adventure)
      adventure.adventure_sheets
        .includes(:feat_definitions, :spell_definitions, adventure_sheet_items: :item_definition)
        .first
    end

    def self.for(sheet, category: nil)
      raise ArgumentError, "CharacterBlock requires a sheet" unless sheet

      case category
      when "combat"    then combat(sheet)
      when "social"    then social(sheet)
      when "traversal" then traversal(sheet)
      else                  full(sheet)
      end
    end

    def self.identity(sheet)
      raise ArgumentError, "CharacterBlock requires a sheet" unless sheet
      "#{sheet.name} — #{sheet.race} #{sheet.character_class} #{sheet.level}"
    end

    def self.full(sheet)
      ds = sheet.derived_stats
      parts = []
      parts << identity_line(sheet)
      parts << conditions_line(sheet)
      parts << ability_scores_line(sheet)
      parts << "HP: #{sheet.hp}/#{sheet.max_hp}  |  Currency: #{format_currency(sheet.currency)}"
      parts << derived_combat_block(ds)
      parts << skills_block(sheet)
      parts << feats_block(sheet)
      parts << spells_block(sheet)
      parts << items_block(sheet)
      parts.reject(&:blank?).join("\n")
    end

    def self.combat(sheet)
      ds = sheet.derived_stats
      parts = []
      parts << identity_line(sheet)
      parts << conditions_line(sheet)
      parts << ability_scores_line(sheet)
      parts << "HP: #{sheet.hp}/#{sheet.max_hp}  |  Currency: #{format_currency(sheet.currency)}"
      parts << derived_combat_block(ds)
      parts << feats_block(sheet, categories: %w[combat general])
      parts << spells_block(sheet)
      parts << items_block(sheet, types: COMBAT_ITEM_TYPES, equipped_only: true)
      parts.reject(&:blank?).join("\n")
    end

    def self.social(sheet)
      parts = []
      parts << identity_line(sheet)
      parts << conditions_line(sheet)
      parts << "CHA: #{sheet.charisma}, WIS: #{sheet.wisdom}, INT: #{sheet.intelligence}  |  Level: #{sheet.level}"
      parts << skills_block(sheet, filter: SOCIAL_SKILLS)
      parts << feats_block(sheet)
      parts << items_block(sheet, types: %w[wondrous], equipped_only: true)
      parts.reject(&:blank?).join("\n")
    end

    def self.traversal(sheet)
      ds = sheet.derived_stats
      parts = []
      parts << identity_line(sheet)
      parts << conditions_line(sheet)
      parts << "STR: #{sheet.strength}, DEX: #{sheet.dexterity}, CON: #{sheet.constitution}, WIS: #{sheet.wisdom}  |  Level: #{sheet.level}"
      parts << "Speed: #{ds['speed'] || 30} ft  |  Encumbrance: #{ds['encumbrance'] || 'light'}  |  Carry: #{format_carry(ds)}"
      parts << skills_block(sheet, filter: TRAVERSAL_SKILLS)
      parts << feats_block(sheet)
      parts << items_block(sheet)
      parts.reject(&:blank?).join("\n")
    end

    def self.creature_stats_for(adventure)
      creatures = adventure.creature_sheets.to_a
      return nil if creatures.empty?

      creatures.map do |c|
        ds = c.derived_stats || {}
        "#{c.name} (#{c.creature_type}): HP #{c.hp}/#{c.max_hp}, AC #{ds['ac']}, " \
          "BAB +#{ds['bab']}, Attitude: #{c.attitude || 'hostile'}"
      end.join("\n")
    end

    # -- private helpers ------------------------------------------------

    def self.identity_line(sheet)
      "#{sheet.name} — #{sheet.race} #{sheet.character_class} #{sheet.level}"
    end

    def self.conditions_line(sheet)
      conds = Array(sheet.try(:conditions))
      return nil if conds.empty?
      "Active Conditions: #{conds.join(', ')}"
    end

    def self.ability_scores_line(sheet)
      "STR: #{sheet.strength}, DEX: #{sheet.dexterity}, CON: #{sheet.constitution}, " \
        "INT: #{sheet.intelligence}, WIS: #{sheet.wisdom}, CHA: #{sheet.charisma}"
    end

    def self.derived_combat_block(ds)
      return "" if ds.blank?

      <<~STATS.strip
        BAB: +#{ds['bab']}  |  AC: #{ds['ac']} (Touch #{ds['touch_ac']}, Flat-Footed #{ds['flat_footed_ac']})
        Fort: #{format_mod(ds['fort'])}  Ref: #{format_mod(ds['ref'])}  Will: #{format_mod(ds['will'])}
        CMB: #{format_mod(ds['cmb'])}  CMD: #{ds['cmd']}  Initiative: #{format_mod(ds['initiative'])}
        Melee: #{format_mod(ds['melee_attack'])}  Ranged: #{format_mod(ds['ranged_attack'])}
        Speed: #{ds['speed']} ft  Size: #{ds['size']}
      STATS
    end

    def self.skills_block(sheet, filter: nil)
      ds = sheet.derived_stats
      return "" if ds.blank? || ds["skills"].blank?

      skills = ds["skills"]
      skills = skills.select { |s| filter.include?(s["name"]) } if filter
      return "" if skills.empty?

      "Skills: " + skills.map { |s| "#{s['name']} #{format_mod(s['total'])}" }.join(", ")
    end

    def self.feats_block(sheet, categories: nil)
      feats = sheet.adventure_sheet_feats.includes(:feat_definition).to_a
      if categories
        feats = feats.select { |f| f.feat_definition && categories.include?(f.feat_definition.category) }
      end
      return "" if feats.empty?

      lines = feats.map do |f|
        fd = f.feat_definition
        next nil unless fd
        f.choice.present? ? "#{fd.name} (#{f.choice})" : fd.name
      end.compact

      "Feats: #{lines.join(', ')}"
    end

    def self.spells_block(sheet)
      spells = sheet.adventure_sheet_spells.includes(:spell_definition).to_a
      return "" if spells.empty?

      lines = spells.map { |s| s.spell_definition&.name }.compact
      "Spells:\n" + lines.map { |name| "  - #{name}" }.join("\n")
    end

    def self.items_block(sheet, types: nil, equipped_only: false)
      items = sheet.adventure_sheet_items.includes(:item_definition).to_a
      items = items.select(&:equipped?) if equipped_only
      items = items.select { |i| i.item_definition && types.include?(i.item_definition.item_type) } if types
      return "" if items.empty?

      lines = items.map do |i|
        next nil unless i.item_definition
        line = i.item_definition.name
        line += " (x#{i.quantity})" if i.quantity && i.quantity > 1
        line += " [equipped]" if i.equipped?
        line
      end.compact

      "Items: #{lines.join(', ')}"
    end

    def self.format_carry(ds)
      caps = ds["carry_capacity"]
      return "unknown" unless caps.is_a?(Hash)
      "#{ds['total_weight'] || '?'}/#{caps['heavy'] || '?'} lbs"
    end

    def self.format_mod(val)
      return "+0" unless val
      val >= 0 ? "+#{val}" : val.to_s
    end

    def self.format_currency(currency)
      return "none" unless currency.is_a?(Hash)
      parts = []
      parts << "#{currency['platinum']} pp" if currency["platinum"].to_i > 0
      parts << "#{currency['gold']} gp"     if currency["gold"].to_i > 0
      parts << "#{currency['silver']} sp"   if currency["silver"].to_i > 0
      parts << "#{currency['copper']} cp"   if currency["copper"].to_i > 0
      parts.empty? ? "none" : parts.join(", ")
    end

    private_class_method :identity_line, :conditions_line, :ability_scores_line,
                         :derived_combat_block, :skills_block, :feats_block,
                         :spells_block, :items_block,
                         :format_carry, :format_mod, :format_currency
  end
end
