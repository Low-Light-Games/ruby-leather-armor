# frozen_string_literal: true

module CharacterStats
  # Thin orchestrator that assembles all derived character stats.
  #
  # Delegates to four focused sub-calculators:
  #   AbilityScoreCalculator — racial mods, conditions, ability mods, BAB
  #   CombatCalculator       — AC, saves, attacks, HP, initiative
  #   EncumbranceCalculator  — carry weight, encumbrance tier, effective speed
  #   SkillCalculator        — skill totals and rank bonuses
  #
  # The public interface is unchanged: Calculator.new(source).compute returns the
  # same Hash as before, suitable for storing in the derived_stats JSONB column.
  class Calculator
    # @param source [Sheet, AdventureSheet, CreatureSheet]
    # @param feats  [Array]  pre-loaded feat pivot records (loaded from DB if nil)
    # @param items  [Array]  pre-loaded item pivot records (loaded from DB if nil)
    def initialize(source, feats: nil, items: nil)
      @src   = source
      @feats = feats || load_feats(source)
      @items = items || load_items(source)
    end

    # Returns the full derived_stats Hash.
    def compute
      ability  = AbilityScoreCalculator.new(@src).compute
      combat   = CombatCalculator.new(@src, feats: @feats, items: @items)
      equip    = combat.compute_equipment_bonuses

      enc = EncumbranceCalculator.new(
        @items,
        str_score:  ability[:final_scores]["strength"],
        size:       ability[:race_info][:size],
        coin_count: @src.total_coins,
      ).compute(base_speed: ability[:race_info][:speed], equip: equip)

      cbt = combat.compute(ability: ability, enc: enc)

      skills = SkillCalculator.new(@src, feats: @feats, items: @items).compute(
        mods:      ability[:mods],
        race_info: ability[:race_info],
        total_acp: cbt[:armor_check_penalty],
      )

      # ── Speed: encumbrance/armor → condition multiplier → active buffs ──
      speed = enc[:effective_speed]
      cond_speed_mult = Conditions.speed_multiplier(ability[:active_conditions])
      speed = (speed * cond_speed_mult).floor if cond_speed_mult < 1.0

      # Apply active_buffs with target: "speed".
      # Stacking rule: group by bonus_type; highest per type; sum distinct types.
      # TODO: extend to target: "str", "dex", etc. when ability-score buff phase lands.
      speed_buffs = Array(@src.try(:active_buffs)).select { |b| b["target"] == "speed" }
      unless speed_buffs.empty?
        buff_speed = speed_buffs
          .group_by { |b| b["bonus_type"] }
          .sum { |_type, group| group.map { |b| b["value"].to_i }.max }
        speed += buff_speed
      end

      {
        final_scores:        ability[:final_scores],
        mods:                ability[:mods],
        bab:                 ability[:bab],
        fort:                cbt[:fort],
        ref:                 cbt[:ref],
        will:                cbt[:will],
        ac:                  cbt[:ac],
        touch_ac:            cbt[:touch_ac],
        flat_footed_ac:      cbt[:flat_footed_ac],
        cmb:                 cbt[:cmb],
        cmd:                 cbt[:cmd],
        initiative:          cbt[:initiative],
        max_hp:              cbt[:max_hp],
        hp_bonus:            cbt[:hp_bonus],
        melee_attack:        cbt[:melee_attack],
        ranged_attack:       cbt[:ranged_attack],
        speed:               speed,
        size:                ability[:race_info][:size],
        skills:              skills,
        feat_stat_bonuses:   cbt[:feat_stat_bonuses],
        armor_bonus:         cbt[:armor_bonus],
        shield_bonus:        cbt[:shield_bonus],
        armor_check_penalty: cbt[:armor_check_penalty],
        arcane_spell_failure: cbt[:arcane_spell_failure],
        max_dex_bonus:       cbt[:max_dex_bonus],
        total_weight:        enc[:total_weight],
        carry_capacity:      enc[:carry_capacity],
        encumbrance:         enc[:encumbrance],
        active_conditions:      ability[:active_conditions],
        condition_restrictions: Conditions.restrictions(ability[:active_conditions]),
        ac_breakdown:        cbt[:ac_breakdown],
        fort_breakdown:      cbt[:fort_breakdown],
        ref_breakdown:       cbt[:ref_breakdown],
        will_breakdown:      cbt[:will_breakdown],
      }
    end

    # Intelligence modifier after racial + optional flex bonus (matches client skill-point budget).
    def self.intelligence_modifier_for_skill_budget(source)
      AbilityScoreCalculator.new(source).compute[:mods]["intelligence"] || 0
    end

    private

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
  end
end
