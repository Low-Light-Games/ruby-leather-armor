# frozen_string_literal: true

module CharacterStats
  # Single source of truth for all derived character stats.
  #
  # Accepts a "stat source" — anything that responds to the same attribute
  # interface as Sheet or AdventureSheet (ability scores, race, class, level,
  # plus associated feat/spell/item pivots).
  #
  # Returns a Hash suitable for storing in a `derived_stats` JSONB column.
  class Calculator
    ABILITIES = %w[strength dexterity constitution intelligence wisdom charisma].freeze

    # ── Class data (OGC mechanical tables) ────────────────────────

    CLASS_DATA = {
      "barbarian"  => { hit_die: 12, bab: "full",  good_saves: %w[fort] },
      "bard"       => { hit_die: 8,  bab: "3/4",   good_saves: %w[ref will] },
      "cleric"     => { hit_die: 8,  bab: "3/4",   good_saves: %w[fort will] },
      "druid"      => { hit_die: 8,  bab: "3/4",   good_saves: %w[fort will] },
      "fighter"    => { hit_die: 10, bab: "full",   good_saves: %w[fort] },
      "monk"       => { hit_die: 8,  bab: "3/4",   good_saves: %w[fort ref will] },
      "paladin"    => { hit_die: 10, bab: "full",   good_saves: %w[fort will] },
      "ranger"     => { hit_die: 10, bab: "full",   good_saves: %w[fort ref] },
      "rogue"      => { hit_die: 8,  bab: "3/4",   good_saves: %w[ref] },
      "sorcerer"   => { hit_die: 6,  bab: "1/2",   good_saves: %w[will] },
      "wizard"     => { hit_die: 6,  bab: "1/2",   good_saves: %w[will] },
    }.freeze

    # ── Race data (OGC mechanical tables) ─────────────────────────

    RACE_DATA = {
      "human"    => { size: "Medium", speed: 30, fixed: {},
                      flex_count: 1, skill_bonuses: {} },
      "elf"      => { size: "Medium", speed: 30,
                      fixed: { "dexterity" => 2, "intelligence" => 2, "constitution" => -2 },
                      flex_count: 0, skill_bonuses: { "Perception" => 2 } },
      "dwarf"    => { size: "Medium", speed: 20,
                      fixed: { "constitution" => 2, "wisdom" => 2, "charisma" => -2 },
                      flex_count: 0, skill_bonuses: {} },
      "halfling" => { size: "Small",  speed: 20,
                      fixed: { "dexterity" => 2, "charisma" => 2, "strength" => -2 },
                      flex_count: 0,
                      skill_bonuses: { "Perception" => 2, "Acrobatics" => 2, "Climb" => 2 } },
      "gnome"    => { size: "Small",  speed: 20,
                      fixed: { "constitution" => 2, "charisma" => 2, "strength" => -2 },
                      flex_count: 0, skill_bonuses: { "Perception" => 2 } },
      "half_elf" => { size: "Medium", speed: 30, fixed: {},
                      flex_count: 1, skill_bonuses: { "Perception" => 2 } },
      "half_orc" => { size: "Medium", speed: 30, fixed: {},
                      flex_count: 1, skill_bonuses: { "Intimidate" => 2 } },
    }.freeze

    # ── Carry capacity table (OGC) — indexed by STR score ─────────
    # Each entry: [light_load_max, medium_load_max, heavy_load_max]
    CARRY_CAPACITY = [
      [0, 0, 0],          # STR 0
      [3, 6, 10],         # STR 1
      [6, 13, 20],        # STR 2
      [10, 20, 30],       # STR 3
      [13, 26, 40],       # STR 4
      [16, 33, 50],       # STR 5
      [20, 40, 60],       # STR 6
      [23, 46, 70],       # STR 7
      [26, 53, 80],       # STR 8
      [30, 60, 90],       # STR 9
      [33, 66, 100],      # STR 10
      [38, 76, 115],      # STR 11
      [43, 86, 130],      # STR 12
      [50, 100, 150],     # STR 13
      [58, 116, 175],     # STR 14
      [66, 133, 200],     # STR 15
      [76, 153, 230],     # STR 16
      [86, 173, 260],     # STR 17
      [100, 200, 300],    # STR 18
      [116, 233, 350],    # STR 19
      [133, 266, 400],    # STR 20
      [153, 306, 460],    # STR 21
      [173, 346, 520],    # STR 22
      [200, 400, 600],    # STR 23
      [233, 466, 700],    # STR 24
      [266, 533, 800],    # STR 25
      [306, 613, 920],    # STR 26
      [346, 693, 1040],   # STR 27
      [400, 800, 1200],   # STR 28
      [466, 933, 1400],   # STR 29
    ].freeze

    # ── Skill table (OGC) ─────────────────────────────────────────

    SKILLS = [
      { name: "Acrobatics",                key: "dexterity",     trained_only: false, acp: true },
      { name: "Appraise",                  key: "intelligence",  trained_only: false, acp: false },
      { name: "Bluff",                     key: "charisma",      trained_only: false, acp: false },
      { name: "Climb",                     key: "strength",      trained_only: false, acp: true },
      { name: "Craft",                     key: "intelligence",  trained_only: false, acp: false },
      { name: "Diplomacy",                 key: "charisma",      trained_only: false, acp: false },
      { name: "Disable Device",            key: "dexterity",     trained_only: true,  acp: true },
      { name: "Disguise",                  key: "charisma",      trained_only: false, acp: false },
      { name: "Escape Artist",             key: "dexterity",     trained_only: false, acp: true },
      { name: "Fly",                       key: "dexterity",     trained_only: false, acp: true },
      { name: "Handle Animal",             key: "charisma",      trained_only: true,  acp: false },
      { name: "Heal",                      key: "wisdom",        trained_only: false, acp: false },
      { name: "Intimidate",               key: "charisma",      trained_only: false, acp: false },
      { name: "Knowledge (Arcana)",        key: "intelligence",  trained_only: true,  acp: false },
      { name: "Knowledge (Dungeoneering)", key: "intelligence",  trained_only: true,  acp: false },
      { name: "Knowledge (Engineering)",   key: "intelligence",  trained_only: true,  acp: false },
      { name: "Knowledge (Geography)",     key: "intelligence",  trained_only: true,  acp: false },
      { name: "Knowledge (History)",       key: "intelligence",  trained_only: true,  acp: false },
      { name: "Knowledge (Local)",         key: "intelligence",  trained_only: true,  acp: false },
      { name: "Knowledge (Nature)",        key: "intelligence",  trained_only: true,  acp: false },
      { name: "Knowledge (Nobility)",      key: "intelligence",  trained_only: true,  acp: false },
      { name: "Knowledge (Planes)",        key: "intelligence",  trained_only: true,  acp: false },
      { name: "Knowledge (Religion)",      key: "intelligence",  trained_only: true,  acp: false },
      { name: "Linguistics",               key: "intelligence",  trained_only: true,  acp: false },
      { name: "Perception",                key: "wisdom",        trained_only: false, acp: false },
      { name: "Perform",                   key: "charisma",      trained_only: false, acp: false },
      { name: "Profession",                key: "wisdom",        trained_only: true,  acp: false },
      { name: "Ride",                      key: "dexterity",     trained_only: false, acp: true },
      { name: "Sense Motive",              key: "wisdom",        trained_only: false, acp: false },
      { name: "Sleight of Hand",           key: "dexterity",     trained_only: true,  acp: true },
      { name: "Spellcraft",               key: "intelligence",  trained_only: true,  acp: false },
      { name: "Stealth",                   key: "dexterity",     trained_only: false, acp: true },
      { name: "Survival",                  key: "wisdom",        trained_only: false, acp: false },
      { name: "Swim",                      key: "strength",      trained_only: false, acp: true },
      { name: "Use Magic Device",          key: "charisma",      trained_only: true,  acp: false },
    ].freeze

    # ── Public interface ──────────────────────────────────────────

    # @param source [Sheet, AdventureSheet] — any object with the expected attributes
    # @param feats  [Array<SheetFeat|AdventureSheetFeat>] — associated feat pivot records
    # @param items  [Array<SheetItem|AdventureSheetItem>] — associated item pivot records (optional)
    def initialize(source, feats: nil, items: nil)
      @src   = source
      @feats = feats || load_feats(source)
      @items = items || load_items(source)
    end

    # Returns the full derived_stats Hash.
    def compute
      race_info  = RACE_DATA[@src.race] || RACE_DATA["human"]
      class_info = CLASS_DATA[@src.character_class]

      # 1. Racial modifiers → final scores → condition penalties → ability mods
      racial_mods   = compute_racial_mods(race_info)
      pre_condition = compute_final_scores(racial_mods)
      final_scores  = apply_condition_penalties(pre_condition)
      mods          = compute_ability_mods(final_scores)

      # 2. BAB (scaled by level)
      bab = class_info ? compute_bab(class_info[:bab], @src.level) : 0

      # 3. Saves (scaled by level)
      good_saves = class_info ? class_info[:good_saves] : []
      fort = compute_base_save(good_saves.include?("fort"), @src.level) + mods["constitution"]
      ref  = compute_base_save(good_saves.include?("ref"),  @src.level) + mods["dexterity"]
      will = compute_base_save(good_saves.include?("will"), @src.level) + mods["wisdom"]

      # 4. Feat bonuses
      feat_skill_bonuses = compute_feat_skill_bonuses
      feat_stat_bonuses  = compute_feat_stat_bonuses

      # Apply feat bonuses to saves
      fort += feat_stat_bonuses[:fort_save]
      ref  += feat_stat_bonuses[:ref_save]
      will += feat_stat_bonuses[:will_save]

      # 5. Equipment bonuses (armor, shield, effects from items)
      equip = compute_equipment_bonuses
      equip_stat_bonuses  = compute_equipment_stat_bonuses
      equip_skill_bonuses = compute_equipment_skill_bonuses

      # Apply equipment effect bonuses to saves
      fort += equip_stat_bonuses[:fort_save]
      ref  += equip_stat_bonuses[:ref_save]
      will += equip_stat_bonuses[:will_save]

      # 6. Carry weight & encumbrance
      size = race_info[:size]
      all_items = @items  # all owned items (equipped or not)
      # Both Sheet and AdventureSheet now have `currency` JSONB + `total_coins`.
      coin_count = @src.total_coins
      total_weight = compute_total_weight(all_items, coin_count)
      carry_caps   = carry_capacity(final_scores["strength"], size)
      encumbrance  = compute_encumbrance_tier(total_weight, carry_caps)
      enc_limits   = encumbrance_limits(encumbrance)

      # 7. Effective DEX modifier — capped by armor max_dex_bonus and encumbrance
      armor_max_dex = equip[:max_dex_bonus]  # nil = no armor limit
      enc_max_dex   = enc_limits[:max_dex]   # nil = no encumbrance limit

      max_dex_caps = [armor_max_dex, enc_max_dex].compact
      effective_max_dex = max_dex_caps.empty? ? nil : max_dex_caps.min
      raw_dex_mod = mods["dexterity"]
      effective_dex_mod = effective_max_dex ? [raw_dex_mod, effective_max_dex].min : raw_dex_mod

      # 8. Total armor check penalty (armor + shield + encumbrance)
      total_acp = equip[:armor_check_penalty] + enc_limits[:acp]

      # 9. Size & combat (using effective DEX)
      ac_size  = size == "Small" ? 1 : 0
      cmb_size = size == "Small" ? -1 : 0

      armor_ac = equip[:armor_bonus]
      shield_ac = equip[:shield_bonus]
      cond_ac_mod = ac_modifier_from_conditions(active_conditions)

      ac    = 10 + effective_dex_mod + ac_size + armor_ac + shield_ac +
              feat_stat_bonuses[:ac] + equip_stat_bonuses[:ac] + cond_ac_mod
      t_ac  = 10 + effective_dex_mod + ac_size +
              feat_stat_bonuses[:ac] + equip_stat_bonuses[:ac] + cond_ac_mod
      ff_ac = 10 + ac_size + armor_ac + shield_ac + cond_ac_mod

      cmb = bab + mods["strength"] + cmb_size
      cmd = 10 + bab + mods["strength"] + effective_dex_mod + cmb_size

      initiative = effective_dex_mod + feat_stat_bonuses[:initiative] + equip_stat_bonuses[:initiative]

      # 10. HP
      hit_die  = class_info ? class_info[:hit_die] : 8
      con_mod  = mods["constitution"]
      hp_bonus = feat_stat_bonuses[:hp] + equip_stat_bonuses[:hp]
      max_hp   = compute_max_hp(hit_die, con_mod, @src.level, hp_bonus)

      # 11. Attack bonuses
      melee_attack  = bab + mods["strength"] + ac_size +
                      feat_stat_bonuses[:melee_attack] + equip_stat_bonuses[:melee_attack]
      ranged_attack = bab + effective_dex_mod + ac_size +
                      feat_stat_bonuses[:ranged_attack] + equip_stat_bonuses[:ranged_attack]

      # 12. Speed (armor may reduce speed, conditions may halve it)
      base_speed = race_info[:speed]
      speed = compute_effective_speed(base_speed, equip, encumbrance)
      cond_speed_mult = Conditions.speed_multiplier(active_conditions)
      speed = (speed * cond_speed_mult).floor if cond_speed_mult < 1.0

      # 13. Arcane spell failure (stacks from armor + shield)
      arcane_spell_failure = equip[:arcane_spell_failure]

      # 14. Skills (with ACP applied to relevant skills)
      skills = compute_skills(mods, race_info, feat_skill_bonuses, equip_skill_bonuses, total_acp)

      # ── Stat breakdowns ──
      ac_breakdown = build_breakdown(
        { label: "Base", value: 10 },
        { label: "Dex Mod", value: effective_dex_mod },
        { label: "Size", value: ac_size },
        { label: "Armor", value: armor_ac },
        { label: "Shield", value: shield_ac },
        { label: "Feat", value: feat_stat_bonuses[:ac] },
        { label: "Equipment", value: equip_stat_bonuses[:ac] },
        *condition_breakdown_entries(active_conditions, :ac_modifiers, "all"),
      )

      fort_breakdown = build_breakdown(
        { label: "Base Save", value: compute_base_save(good_saves.include?("fort"), @src.level) },
        { label: "CON Mod", value: mods["constitution"] },
        { label: "Feat", value: feat_stat_bonuses[:fort_save] },
        { label: "Equipment", value: equip_stat_bonuses[:fort_save] },
      )

      ref_breakdown = build_breakdown(
        { label: "Base Save", value: compute_base_save(good_saves.include?("ref"), @src.level) },
        { label: "DEX Mod", value: mods["dexterity"] },
        { label: "Feat", value: feat_stat_bonuses[:ref_save] },
        { label: "Equipment", value: equip_stat_bonuses[:ref_save] },
      )

      will_breakdown = build_breakdown(
        { label: "Base Save", value: compute_base_save(good_saves.include?("will"), @src.level) },
        { label: "WIS Mod", value: mods["wisdom"] },
        { label: "Feat", value: feat_stat_bonuses[:will_save] },
        { label: "Equipment", value: equip_stat_bonuses[:will_save] },
      )

      {
        final_scores: final_scores,
        mods: mods,
        bab: bab,
        fort: fort,
        ref: ref,
        will: will,
        ac: ac,
        touch_ac: t_ac,
        flat_footed_ac: ff_ac,
        cmb: cmb,
        cmd: cmd,
        initiative: initiative,
        max_hp: max_hp,
        hp_bonus: hp_bonus,
        melee_attack: melee_attack,
        ranged_attack: ranged_attack,
        speed: speed,
        size: size,
        skills: skills,
        feat_stat_bonuses: feat_stat_bonuses,
        # ── Equipment-derived stats ──
        armor_bonus: armor_ac,
        shield_bonus: shield_ac,
        armor_check_penalty: total_acp,
        arcane_spell_failure: arcane_spell_failure,
        max_dex_bonus: effective_max_dex,
        total_weight: total_weight.round(2),
        carry_capacity: {
          light: carry_caps[0],
          medium: carry_caps[1],
          heavy: carry_caps[2],
        },
        encumbrance: encumbrance,
        # ── Condition data ──
        active_conditions: active_conditions,
        condition_restrictions: Conditions.restrictions(active_conditions),
        # ── Stat breakdowns ──
        ac_breakdown: ac_breakdown,
        fort_breakdown: fort_breakdown,
        ref_breakdown: ref_breakdown,
        will_breakdown: will_breakdown,
      }
    end

    private

    # ── Conditions ──────────────────────────────────────────────

    def active_conditions
      @active_conditions ||= Array(@src.try(:conditions))
    end

    def apply_condition_penalties(scores)
      conds = active_conditions
      return scores if conds.empty?

      adjusted = scores.dup
      Conditions.effective_scores(conds).each do |ability, value|
        adjusted[ability] = value
      end
      Conditions.ability_penalties(conds).each do |ability, penalty|
        next if Conditions.effective_scores(conds).key?(ability)
        adjusted[ability] = (adjusted[ability] + penalty).clamp(0, 99)
      end
      adjusted
    end

    def ac_modifier_from_conditions(conds)
      total = 0
      conds.each do |cond_name|
        defn = Conditions::DEFINITIONS[cond_name]
        next unless defn && defn[:ac_modifiers]
        total += defn[:ac_modifiers]["all"].to_i
      end
      total
    end

    def build_breakdown(*entries)
      entries.flatten.select { |e| e[:value].to_i != 0 || e[:label] == "Base" }
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

    # ── Ability score pipeline ────────────────────────────────────

    def compute_racial_mods(race_info)
      mods = ABILITIES.each_with_object({}) { |a, h| h[a] = 0 }
      (race_info[:fixed] || {}).each { |a, v| mods[a] += v }
      if race_info[:flex_count].to_i > 0 && @src.racial_bonus_attribute.present?
        mods[@src.racial_bonus_attribute] += 2
      end
      mods
    end

    def compute_final_scores(racial_mods)
      ABILITIES.each_with_object({}) do |a, h|
        h[a] = @src.send(a) + (racial_mods[a] || 0)
      end
    end

    def compute_ability_mods(final_scores)
      final_scores.transform_values { |v| ((v - 10).to_f / 2).floor }
    end

    # ── BAB ───────────────────────────────────────────────────────

    def compute_bab(progression, level)
      case progression
      when "full"  then level
      when "3/4"   then (level * 3 / 4.0).floor
      when "1/2"   then (level / 2.0).floor
      else 0
      end
    end

    # ── Saves ─────────────────────────────────────────────────────

    # Pathfinder 1e:
    #   Good save: floor(level / 2) + 2
    #   Poor save: floor((level - 1) / 3)
    def compute_base_save(good, level)
      if good
        (level / 2.0).floor + 2
      else
        ((level - 1) / 3.0).floor
      end
    end

    # ── HP ────────────────────────────────────────────────────────

    def compute_max_hp(hit_die, con_mod, level, hp_bonus)
      # Level 1: max hit die + CON mod (min 1)
      lv1 = [hit_die + con_mod, 1].max
      # Levels 2+: (hit_die / 2 + 1) + CON mod per level (min 1 each)
      per_level = [(hit_die / 2) + 1 + con_mod, 1].max
      total = lv1 + (level - 1) * per_level + hp_bonus
      [total, 1].max
    end

    # ── Feats ─────────────────────────────────────────────────────

    def load_feats(source)
      if source.respond_to?(:sheet_feats)
        source.sheet_feats.includes(:feat_definition)
      elsif source.respond_to?(:adventure_sheet_feats)
        source.adventure_sheet_feats.includes(:feat_definition)
      elsif source.respond_to?(:creature_sheet_feats)
        source.creature_sheet_feats.includes(:feat_definition)
      else
        []
      end
    end

    # Returns { "Perception" => 3, "Stealth" => 2, ... }
    def compute_feat_skill_bonuses
      bonuses = {}
      @feats.each do |sf|
        fd = sf.feat_definition
        next unless fd

        (fd.effects || []).each do |effect|
          next unless effect["type"] == "skill_bonus"

          target = effect["skill"]
          # For parameterised feats (Skill Focus), replace placeholder with actual choice
          target = sf.choice if target == "chosen skill" && sf.choice.present?
          next if target.blank?

          bonuses[target] = (bonuses[target] || 0) + (effect["bonus"] || 0)
        end
      end
      bonuses
    end

    # Returns { ac: N, fort_save: N, ref_save: N, will_save: N,
    #           initiative: N, melee_attack: N, ranged_attack: N,
    #           hp: N, cmb_by_maneuver: {}, cmd_by_maneuver: {} }
    def compute_feat_stat_bonuses
      result = {
        ac: 0, fort_save: 0, ref_save: 0, will_save: 0,
        initiative: 0, melee_attack: 0, ranged_attack: 0,
        hp: 0, cmb_by_maneuver: {}, cmd_by_maneuver: {},
      }

      @feats.each do |sf|
        fd = sf.feat_definition
        next unless fd

        (fd.effects || []).each do |effect|
          case effect["type"]
          when "bonus"
            next if effect["condition"].present? # skip conditional bonuses

            case effect["target"]
            when "ac"           then result[:ac] += (effect["bonus"] || 0)
            when "fort_save"    then result[:fort_save] += (effect["bonus"] || 0)
            when "ref_save"     then result[:ref_save] += (effect["bonus"] || 0)
            when "will_save"    then result[:will_save] += (effect["bonus"] || 0)
            when "all_saves"
              b = effect["bonus"] || 0
              result[:fort_save] += b
              result[:ref_save]  += b
              result[:will_save] += b
            when "initiative"    then result[:initiative] += (effect["bonus"] || 0)
            when "attack"
              b = effect["bonus"] || 0
              result[:melee_attack]  += b
              result[:ranged_attack] += b
            when "melee_attack"  then result[:melee_attack] += (effect["bonus"] || 0)
            when "ranged_attack" then result[:ranged_attack] += (effect["bonus"] || 0)
            end

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

    # ── Items / Equipment ─────────────────────────────────────────

    def load_items(source)
      if source.respond_to?(:sheet_items)
        source.sheet_items.includes(:item_definition)
      elsif source.respond_to?(:adventure_sheet_items)
        source.adventure_sheet_items.includes(:item_definition)
      elsif source.respond_to?(:creature_sheet_items)
        source.creature_sheet_items.includes(:item_definition)
      else
        []
      end
    end

    # Aggregate bonuses from equipped armor/shield items.
    # Returns { armor_bonus:, shield_bonus:, max_dex_bonus:, armor_check_penalty:,
    #           arcane_spell_failure:, speed_30:, speed_20: }
    def compute_equipment_bonuses
      result = {
        armor_bonus: 0,
        shield_bonus: 0,
        max_dex_bonus: nil,       # nil = no limit
        armor_check_penalty: 0,   # negative number
        arcane_spell_failure: 0,  # percentage
        speed_30: nil,            # armor speed for base 30
        speed_20: nil,            # armor speed for base 20
      }

      equipped = @items.select(&:equipped?)

      equipped.each do |si|
        item = si.item_definition
        next unless item

        result[:armor_bonus]  += item.armor_bonus
        result[:shield_bonus] += item.shield_bonus
        result[:armor_check_penalty] += item.armor_check_penalty if item.armor_check_penalty.present? # already negative
        result[:arcane_spell_failure] += item.arcane_spell_failure

        # Max DEX bonus: take the most restrictive (lowest non-nil)
        if item.max_dex_bonus
          result[:max_dex_bonus] = if result[:max_dex_bonus]
                                     [result[:max_dex_bonus], item.max_dex_bonus].min
                                   else
                                     item.max_dex_bonus
                                   end
        end

        # Speed from armor (only armor type sets this, not shields)
        if item.item_type == "armor"
          result[:speed_30] = item.speed_30 if item.speed_30
          result[:speed_20] = item.speed_20 if item.speed_20
        end
      end

      result
    end

    # Stat bonuses from equipped item effects (same schema as feat effects)
    def compute_equipment_stat_bonuses
      result = {
        ac: 0, fort_save: 0, ref_save: 0, will_save: 0,
        initiative: 0, melee_attack: 0, ranged_attack: 0,
        hp: 0, cmb_by_maneuver: {}, cmd_by_maneuver: {},
      }

      equipped = @items.select(&:equipped?)

      equipped.each do |si|
        item = si.item_definition
        next unless item

        (item.effects || []).each do |effect|
          case effect["type"]
          when "bonus"
            next if effect["condition"].present?

            case effect["target"]
            when "ac"           then result[:ac] += (effect["bonus"] || 0)
            when "fort_save"    then result[:fort_save] += (effect["bonus"] || 0)
            when "ref_save"     then result[:ref_save] += (effect["bonus"] || 0)
            when "will_save"    then result[:will_save] += (effect["bonus"] || 0)
            when "all_saves"
              b = effect["bonus"] || 0
              result[:fort_save] += b
              result[:ref_save]  += b
              result[:will_save] += b
            when "initiative"    then result[:initiative] += (effect["bonus"] || 0)
            when "attack"
              b = effect["bonus"] || 0
              result[:melee_attack]  += b
              result[:ranged_attack] += b
            when "melee_attack"  then result[:melee_attack] += (effect["bonus"] || 0)
            when "ranged_attack" then result[:ranged_attack] += (effect["bonus"] || 0)
            end
          when "hp_bonus"
            per_level = effect["perLevel"] || 0
            minimum   = effect["minimum"] || 0
            result[:hp] += [per_level * @src.level, minimum].max
          end
        end
      end

      result
    end

    # Skill bonuses from equipped item effects
    def compute_equipment_skill_bonuses
      bonuses = {}

      equipped = @items.select(&:equipped?)

      equipped.each do |si|
        item = si.item_definition
        next unless item

        (item.effects || []).each do |effect|
          next unless effect["type"] == "skill_bonus"
          target = effect["skill"]
          next if target.blank?

          bonuses[target] = (bonuses[target] || 0) + (effect["bonus"] || 0)
        end
      end

      bonuses
    end

    # ── Carry weight & encumbrance ────────────────────────────────

    # Total weight of all owned items + coin weight
    def compute_total_weight(items, gold)
      item_weight = items.sum do |si|
        item = si.item_definition
        next 0.0 unless item
        (item.weight || 0).to_f * (si.quantity || 1)
      end

      # 50 coins = 1 lb (Pathfinder 1e)
      coin_weight = gold.to_f / 50.0

      item_weight + coin_weight
    end

    # Returns [light_max, medium_max, heavy_max] for a given STR score and size
    def carry_capacity(str_score, size)
      str = [str_score, 0].max
      caps = if str < CARRY_CAPACITY.length
               CARRY_CAPACITY[str]
             else
               # For STR > 29: each +10 over 20 multiplies base by 4
               base = CARRY_CAPACITY[20]
               tens = ((str - 20) / 10.0).floor
               remainder = (str - 20) % 10
               rem_caps = remainder < 10 ? (CARRY_CAPACITY[20 + remainder] || CARRY_CAPACITY.last) : CARRY_CAPACITY.last
               multiplier = 4**tens
               rem_caps.map { |v| v * multiplier }
             end

      # Small creatures carry 3/4 of Medium
      if size == "Small"
        caps.map { |v| (v * 0.75).floor }
      else
        caps
      end
    end

    # Returns :light, :medium, :heavy, or :overloaded
    def compute_encumbrance_tier(total_weight, carry_caps)
      light_max, medium_max, heavy_max = carry_caps

      if total_weight <= light_max
        :light
      elsif total_weight <= medium_max
        :medium
      elsif total_weight <= heavy_max
        :heavy
      else
        :overloaded
      end
    end

    # Returns { max_dex: N|nil, acp: N, run_multiplier: N }
    def encumbrance_limits(tier)
      case tier
      when :light
        { max_dex: nil, acp: 0, run_multiplier: 4 }
      when :medium
        { max_dex: 3, acp: -3, run_multiplier: 4 }
      when :heavy
        { max_dex: 1, acp: -6, run_multiplier: 3 }
      when :overloaded
        { max_dex: 0, acp: -6, run_multiplier: 0 }
      else
        { max_dex: nil, acp: 0, run_multiplier: 4 }
      end
    end

    # ── Speed ─────────────────────────────────────────────────────

    def compute_effective_speed(base_speed, equip, encumbrance)
      # Armor may set a specific speed for base 30 or base 20
      armor_speed = base_speed >= 30 ? equip[:speed_30] : equip[:speed_20]

      # Encumbrance (medium/heavy) reduces speed:
      #   30 → 20, 20 → 15
      enc_speed = if encumbrance == :medium || encumbrance == :heavy || encumbrance == :overloaded
                    base_speed >= 30 ? 20 : 15
                  else
                    base_speed
                  end

      # Take the most restrictive (lowest)
      speeds = [armor_speed, enc_speed].compact
      speeds.empty? ? base_speed : speeds.min
    end

    # ── Skills ────────────────────────────────────────────────────

    def compute_skills(mods, race_info, feat_skill_bonuses, equip_skill_bonuses = {}, total_acp = 0)
      racial_skills = race_info[:skill_bonuses] || {}

      SKILLS.map do |skill|
        ability_mod  = mods[skill[:key]] || 0
        racial_bonus = racial_skills[skill[:name]] || 0
        feat_bonus   = feat_skill_bonuses[skill[:name]] || 0
        equip_bonus  = equip_skill_bonuses[skill[:name]] || 0
        acp_penalty  = skill[:acp] ? total_acp : 0  # total_acp is already negative
        total        = ability_mod + racial_bonus + feat_bonus + equip_bonus + acp_penalty

        {
          name: skill[:name],
          key_ability: skill[:key],
          trained_only: skill[:trained_only],
          ability_mod: ability_mod,
          racial_bonus: racial_bonus,
          feat_bonus: feat_bonus,
          equip_bonus: equip_bonus,
          acp_penalty: acp_penalty,
          total: total,
        }
      end
    end
  end
end
