# frozen_string_literal: true

module CharacterStats
  class CombatCalculator
    include GameRules

    # @param source [Sheet, AdventureSheet, AdventureActorSheet]
    # @param feats  [Array<SheetFeat|AdventureSheetFeat>]  pre-loaded pivot records
    # @param items  [Array<SheetItem|AdventureSheetItem>]  pre-loaded pivot records
    def initialize(source, feats:, items:)
      @src   = source
      @feats = feats
      @items = items
    end

    # @param ability [Hash] output of AbilityScoreCalculator#compute
    # @param enc     [Hash] output of EncumbranceCalculator#compute
    # @return [Hash] all combat stats
    def compute(ability:, enc:)
      mods             = ability[:mods]
      bab              = ability[:bab]
      good_saves       = ability[:good_saves]
      active_conds     = ability[:active_conditions]
      race_info        = ability[:race_info]
      class_info       = ability[:class_info]
      final_scores     = ability[:final_scores]

      feat_stat_bonuses  = compute_feat_stat_bonuses
      equip              = compute_equipment_bonuses
      equip_stat_bonuses = compute_equipment_stat_bonuses

      active_buff_rows = PersistedJsonArray.list(@src.try(:active_buffs))
      save_buff        = ActiveBuffStacking.stacked_value_for_target(active_buff_rows, "saves")
      attack_buff      = ActiveBuffStacking.stacked_value_for_target(active_buff_rows, "attack")
      damage_buff      = ActiveBuffStacking.stacked_value_for_target(active_buff_rows, "damage")

      fort = compute_base_save(good_saves.include?("fort"), @src.level) +
             mods["constitution"] + feat_stat_bonuses[:fort_save] + equip_stat_bonuses[:fort_save] + save_buff
      ref  = compute_base_save(good_saves.include?("ref"),  @src.level) +
             mods["dexterity"] + feat_stat_bonuses[:ref_save] + equip_stat_bonuses[:ref_save] + save_buff
      will = compute_base_save(good_saves.include?("will"), @src.level) +
             mods["wisdom"] + feat_stat_bonuses[:will_save] + equip_stat_bonuses[:will_save] + save_buff

      enc_limits    = enc[:enc_limits]
      armor_max_dex = equip[:max_dex_bonus]
      enc_max_dex   = enc_limits[:max_dex]

      max_dex_caps      = [armor_max_dex, enc_max_dex].compact
      effective_max_dex = max_dex_caps.empty? ? nil : max_dex_caps.min
      raw_dex_mod       = mods["dexterity"]
      effective_dex_mod = effective_max_dex ? [raw_dex_mod, effective_max_dex].min : raw_dex_mod

      total_acp = equip[:armor_check_penalty] + enc_limits[:acp]

      size     = race_info[:size]
      ac_size  = size == "Small" ? 1 : 0
      cmb_size = size == "Small" ? -1 : 0

      ac_buff_max_by_type = ActiveBuffStacking.max_per_bonus_type_for_target(active_buff_rows, "ac")

      cond_ac_mod = ac_modifier_from_conditions(active_conds)

      armor_buff  = ac_buff_max_by_type.delete("armor") || 0
      shield_buff = ac_buff_max_by_type.delete("shield") || 0
      armor_ac  = [equip[:armor_bonus],  armor_buff].max
      shield_ac = [equip[:shield_bonus], shield_buff].max

      other_buff_ac = ac_buff_max_by_type.values.sum

      ac    = 10 + effective_dex_mod + ac_size + armor_ac + shield_ac +
              feat_stat_bonuses[:ac] + equip_stat_bonuses[:ac] + cond_ac_mod + other_buff_ac
      t_ac  = 10 + effective_dex_mod + ac_size +
              feat_stat_bonuses[:ac] + equip_stat_bonuses[:ac] + cond_ac_mod + other_buff_ac
      ff_ac = 10 + ac_size + armor_ac + shield_ac + cond_ac_mod + other_buff_ac

      cmb        = bab + mods["strength"] + cmb_size
      cmd        = 10 + bab + mods["strength"] + effective_dex_mod + cmb_size
      initiative = effective_dex_mod + feat_stat_bonuses[:initiative] + equip_stat_bonuses[:initiative]

      hit_die  = class_info ? class_info[:hit_die] : 8
      hp_bonus = feat_stat_bonuses[:hp] + equip_stat_bonuses[:hp]
      max_hp   = compute_max_hp(hit_die, mods["constitution"], @src.level, hp_bonus)

      melee_attack  = bab + mods["strength"] + ac_size +
                      feat_stat_bonuses[:melee_attack] + equip_stat_bonuses[:melee_attack] + attack_buff
      ranged_attack = bab + effective_dex_mod + ac_size +
                      feat_stat_bonuses[:ranged_attack] + equip_stat_bonuses[:ranged_attack] + attack_buff

      buff_breakdown_entries = ac_buff_max_by_type.filter_map do |bonus_type, val|
        { label: "Buff (#{bonus_type})", value: val } if val.nonzero?
      end

      ac_breakdown   = build_breakdown(
        { label: "Base",      value: 10 },
        { label: "Dex Mod",   value: effective_dex_mod },
        { label: "Size",      value: ac_size },
        { label: "Armor",     value: armor_ac },
        { label: "Shield",    value: shield_ac },
        { label: "Feat",      value: feat_stat_bonuses[:ac] },
        { label: "Equipment", value: equip_stat_bonuses[:ac] },
        *condition_breakdown_entries(active_conds, :ac_modifiers, "all"),
        *buff_breakdown_entries,
      )
      fort_breakdown = build_breakdown(
        { label: "Base Save", value: compute_base_save(good_saves.include?("fort"), @src.level) },
        { label: "CON Mod",   value: mods["constitution"] },
        { label: "Feat",      value: feat_stat_bonuses[:fort_save] },
        { label: "Equipment", value: equip_stat_bonuses[:fort_save] },
        buff_save_breakdown_line(save_buff),
      )
      ref_breakdown = build_breakdown(
        { label: "Base Save", value: compute_base_save(good_saves.include?("ref"), @src.level) },
        { label: "DEX Mod",   value: mods["dexterity"] },
        { label: "Feat",      value: feat_stat_bonuses[:ref_save] },
        { label: "Equipment", value: equip_stat_bonuses[:ref_save] },
        buff_save_breakdown_line(save_buff),
      )
      will_breakdown = build_breakdown(
        { label: "Base Save", value: compute_base_save(good_saves.include?("will"), @src.level) },
        { label: "WIS Mod",   value: mods["wisdom"] },
        { label: "Feat",      value: feat_stat_bonuses[:will_save] },
        { label: "Equipment", value: equip_stat_bonuses[:will_save] },
        buff_save_breakdown_line(save_buff),
      )

      {
        ac: ac, touch_ac: t_ac, flat_footed_ac: ff_ac,
        cmb: cmb, cmd: cmd, initiative: initiative,
        fort: fort, ref: ref, will: will,
        max_hp: max_hp, hp_bonus: hp_bonus,
        melee_attack: melee_attack, ranged_attack: ranged_attack,
        damage_bonus: damage_buff,
        feat_stat_bonuses: feat_stat_bonuses,
        armor_bonus: armor_ac, shield_bonus: shield_ac,
        armor_check_penalty: total_acp,
        arcane_spell_failure: equip[:arcane_spell_failure],
        max_dex_bonus: effective_max_dex,
        equip: equip,
        ac_breakdown: ac_breakdown, fort_breakdown: fort_breakdown,
        ref_breakdown: ref_breakdown, will_breakdown: will_breakdown,
      }
    end

    def compute_equipment_bonuses
      result = empty_equipment_bonuses

      @items.select(&:equipped?).each do |si|
        item = si.item_definition
        next unless item

        result[:armor_bonus]  += item.armor_bonus
        result[:shield_bonus] += item.shield_bonus
        result[:armor_check_penalty] += item.armor_check_penalty if item.armor_check_penalty.present?
        result[:arcane_spell_failure] += item.arcane_spell_failure

        if item.max_dex_bonus
          result[:max_dex_bonus] = if result[:max_dex_bonus]
                                     [result[:max_dex_bonus], item.max_dex_bonus].min
                                   else
                                     item.max_dex_bonus
                                   end
        end

        if item.item_type == "armor"
          result[:speed_30] = item.speed_30 if item.speed_30
          result[:speed_20] = item.speed_20 if item.speed_20
        end
      end

      result
    end

    private

    def compute_base_save(good, level)
      good ? (level / 2.0).floor + 2 : ((level - 1) / 3.0).floor
    end

    def compute_max_hp(hit_die, con_mod, level, hp_bonus)
      lv1       = [hit_die + con_mod, 1].max
      per_level = [(hit_die / 2) + 1 + con_mod, 1].max
      [[lv1 + (level - 1) * per_level + hp_bonus, 1].max, 1].max
    end

    def compute_feat_stat_bonuses
      result = empty_stat_bonuses

      @feats.each do |sf|
        fd = sf.feat_definition
        next unless fd

        (fd.effects || []).each do |effect|
          case effect["type"]
          when "bonus"
            next if effect["condition"].present?

            apply_bonus_effect(result, effect)
          when "hp_bonus"
            per_level = effect["perLevel"] || 0
            minimum   = effect["minimum"] || 0
            result[:hp] += [per_level * @src.level, minimum].max
          when "combat_maneuver"
            m = effect["maneuver"]
            result[:cmb_by_maneuver][m] = (result[:cmb_by_maneuver][m] || 0) + (effect["cmbBonus"] || 0)
            result[:cmd_by_maneuver][m] = (result[:cmd_by_maneuver][m] || 0) + (effect["cmdBonus"] || 0)
          end
        end
      end

      result
    end

    def compute_equipment_stat_bonuses
      result = empty_stat_bonuses

      @items.select(&:equipped?).each do |si|
        item = si.item_definition
        next unless item

        (item.effects || []).each do |effect|
          case effect["type"]
          when "bonus"
            next if effect["condition"].present?

            apply_bonus_effect(result, effect)
          when "hp_bonus"
            per_level = effect["perLevel"] || 0
            minimum   = effect["minimum"] || 0
            result[:hp] += [per_level * @src.level, minimum].max
          end
        end
      end

      result
    end

    def apply_bonus_effect(result, effect)
      b = effect["bonus"] || 0
      case effect["target"]
      when "ac"            then result[:ac] += b
      when "fort_save"     then result[:fort_save] += b
      when "ref_save"      then result[:ref_save] += b
      when "will_save"     then result[:will_save] += b
      when "all_saves"
        result[:fort_save] += b
        result[:ref_save]  += b
        result[:will_save] += b
      when "initiative"    then result[:initiative] += b
      when "attack"
        result[:melee_attack]  += b
        result[:ranged_attack] += b
      when "melee_attack"  then result[:melee_attack] += b
      when "ranged_attack" then result[:ranged_attack] += b
      end
    end

    def empty_equipment_bonuses
      {
        armor_bonus: 0,
        shield_bonus: 0,
        max_dex_bonus: nil,
        armor_check_penalty: 0,
        arcane_spell_failure: 0,
        speed_30: nil,
        speed_20: nil,
      }
    end

    def buff_save_breakdown_line(save_buff)
      return nil if save_buff.to_i.zero?

      { label: "Buff (saves target)", value: save_buff, type: "bonus" }
    end

    def empty_stat_bonuses
      {
        ac: 0,
        fort_save: 0,
        ref_save: 0,
        will_save: 0,
        initiative: 0,
        melee_attack: 0,
        ranged_attack: 0,
        hp: 0,
        cmb_by_maneuver: {},
        cmd_by_maneuver: {},
      }
    end

    def ac_modifier_from_conditions(conds)
      conds.sum do |cond_name|
        defn = Conditions::DEFINITIONS[cond_name]
        defn && defn[:ac_modifiers] ? defn[:ac_modifiers]["all"].to_i : 0
      end
    end

    def build_breakdown(*entries)
      entries.flatten.compact.select { |e| e[:value].to_i != 0 || e[:label] == "Base" }
    end

    def condition_breakdown_entries(conds, effect_key, sub_key)
      conds.filter_map do |cond_name|
        defn = Conditions::DEFINITIONS[cond_name]
        next unless defn && defn[effect_key]

        value = defn[effect_key][sub_key].to_i
        next if value == 0

        { label: cond_name.capitalize, value: value, type: "condition" }
      end
    end
  end
end
