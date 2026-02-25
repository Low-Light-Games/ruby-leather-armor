# frozen_string_literal: true

module CharacterStats
  # Single source of truth for all derived character stats.
  #
  # Accepts a "stat source" — anything that responds to the same attribute
  # interface as Sheet or AdventureSheet (ability scores, race, class, level,
  # plus associated feat/spell pivots).
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

    # ── Skill table (OGC) ─────────────────────────────────────────

    SKILLS = [
      { name: "Acrobatics",                key: "dexterity",     trained_only: false },
      { name: "Appraise",                  key: "intelligence",  trained_only: false },
      { name: "Bluff",                     key: "charisma",      trained_only: false },
      { name: "Climb",                     key: "strength",      trained_only: false },
      { name: "Craft",                     key: "intelligence",  trained_only: false },
      { name: "Diplomacy",                 key: "charisma",      trained_only: false },
      { name: "Disable Device",            key: "dexterity",     trained_only: true  },
      { name: "Disguise",                  key: "charisma",      trained_only: false },
      { name: "Escape Artist",             key: "dexterity",     trained_only: false },
      { name: "Fly",                       key: "dexterity",     trained_only: false },
      { name: "Handle Animal",             key: "charisma",      trained_only: true  },
      { name: "Heal",                      key: "wisdom",        trained_only: false },
      { name: "Intimidate",               key: "charisma",      trained_only: false },
      { name: "Knowledge (Arcana)",        key: "intelligence",  trained_only: true  },
      { name: "Knowledge (Dungeoneering)", key: "intelligence",  trained_only: true  },
      { name: "Knowledge (Engineering)",   key: "intelligence",  trained_only: true  },
      { name: "Knowledge (Geography)",     key: "intelligence",  trained_only: true  },
      { name: "Knowledge (History)",       key: "intelligence",  trained_only: true  },
      { name: "Knowledge (Local)",         key: "intelligence",  trained_only: true  },
      { name: "Knowledge (Nature)",        key: "intelligence",  trained_only: true  },
      { name: "Knowledge (Nobility)",      key: "intelligence",  trained_only: true  },
      { name: "Knowledge (Planes)",        key: "intelligence",  trained_only: true  },
      { name: "Knowledge (Religion)",      key: "intelligence",  trained_only: true  },
      { name: "Linguistics",               key: "intelligence",  trained_only: true  },
      { name: "Perception",                key: "wisdom",        trained_only: false },
      { name: "Perform",                   key: "charisma",      trained_only: false },
      { name: "Profession",                key: "wisdom",        trained_only: true  },
      { name: "Ride",                      key: "dexterity",     trained_only: false },
      { name: "Sense Motive",              key: "wisdom",        trained_only: false },
      { name: "Sleight of Hand",           key: "dexterity",     trained_only: true  },
      { name: "Spellcraft",               key: "intelligence",  trained_only: true  },
      { name: "Stealth",                   key: "dexterity",     trained_only: false },
      { name: "Survival",                  key: "wisdom",        trained_only: false },
      { name: "Swim",                      key: "strength",      trained_only: false },
      { name: "Use Magic Device",          key: "charisma",      trained_only: true  },
    ].freeze

    # ── Public interface ──────────────────────────────────────────

    # @param source [Sheet, AdventureSheet] — any object with the expected attributes
    # @param feats  [Array<SheetFeat|AdventureSheetFeat>] — associated feat pivot records
    def initialize(source, feats: nil)
      @src   = source
      @feats = feats || load_feats(source)
    end

    # Returns the full derived_stats Hash.
    def compute
      race_info  = RACE_DATA[@src.race] || RACE_DATA["human"]
      class_info = CLASS_DATA[@src.character_class]

      # 1. Racial modifiers → final scores → ability mods
      racial_mods  = compute_racial_mods(race_info)
      final_scores = compute_final_scores(racial_mods)
      mods         = compute_ability_mods(final_scores)

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

      # 5. Size & combat
      size = race_info[:size]
      ac_size = size == "Small" ? 1 : 0
      cmb_size = size == "Small" ? -1 : 0

      ac    = 10 + mods["dexterity"] + ac_size + feat_stat_bonuses[:ac]
      t_ac  = 10 + mods["dexterity"] + ac_size + feat_stat_bonuses[:ac]
      ff_ac = 10 + ac_size # no DEX, no dodge
      cmb   = bab + mods["strength"] + cmb_size
      cmd   = 10 + bab + mods["strength"] + mods["dexterity"] + cmb_size

      initiative = mods["dexterity"] + feat_stat_bonuses[:initiative]

      # 6. HP
      hit_die  = class_info ? class_info[:hit_die] : 8
      con_mod  = mods["constitution"]
      hp_bonus = feat_stat_bonuses[:hp]
      max_hp   = compute_max_hp(hit_die, con_mod, @src.level, hp_bonus)

      # 7. Attack bonuses
      melee_attack  = bab + mods["strength"] + ac_size + feat_stat_bonuses[:melee_attack]
      ranged_attack = bab + mods["dexterity"] + ac_size + feat_stat_bonuses[:ranged_attack]

      # 8. Skills
      skills = compute_skills(mods, race_info, feat_skill_bonuses)

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
        speed: race_info[:speed],
        size: size,
        skills: skills,
        feat_stat_bonuses: feat_stat_bonuses,
      }
    end

    private

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

    # ── Skills ────────────────────────────────────────────────────

    def compute_skills(mods, race_info, feat_skill_bonuses)
      racial_skills = race_info[:skill_bonuses] || {}

      SKILLS.map do |skill|
        ability_mod  = mods[skill[:key]] || 0
        racial_bonus = racial_skills[skill[:name]] || 0
        feat_bonus   = feat_skill_bonuses[skill[:name]] || 0
        total        = ability_mod + racial_bonus + feat_bonus

        {
          name: skill[:name],
          key_ability: skill[:key],
          trained_only: skill[:trained_only],
          ability_mod: ability_mod,
          racial_bonus: racial_bonus,
          feat_bonus: feat_bonus,
          total: total,
        }
      end
    end
  end
end
