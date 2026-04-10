# frozen_string_literal: true

module CharacterStats
  # Computes the full skill list for a character, including rank bonuses,
  # racial bonuses, feat bonuses, equipment bonuses, and ACP penalties.
  #
  # Skill rank budget enforcement and cap logic mirror the client-side rules in
  # app/javascript/rules/pathfinder_skill_ranks.ts.
  class SkillCalculator
    include GameRules

    # @param source [Sheet, AdventureSheet, CreatureSheet]
    # @param feats  [Array<SheetFeat|AdventureSheetFeat>]  pre-loaded pivot records
    # @param items  [Array<SheetItem|AdventureSheetItem>]  pre-loaded pivot records
    def initialize(source, feats:, items:)
      @src   = source
      @feats = feats
      @items = items
    end

    # @param mods      [Hash]  ability score modifiers, e.g. { "dexterity" => 3 }
    # @param race_info [Hash]  entry from GameRules::RACE_DATA
    # @param total_acp [Integer] total armor check penalty (already negative)
    # @return [Array<Hash>] one entry per skill in GameRules::SKILLS
    def compute(mods:, race_info:, total_acp:)
      feat_bonuses  = compute_feat_skill_bonuses
      equip_bonuses = compute_equipment_skill_bonuses
      compute_skills(mods, race_info, feat_bonuses, equip_bonuses, total_acp)
    end

    private

    def compute_skills(mods, race_info, feat_skill_bonuses, equip_skill_bonuses, total_acp)
      racial_skills = race_info[:skill_bonuses] || {}
      ranks_map     = skill_ranks_raw

      SKILLS.map do |skill|
        ability_mod  = mods[skill[:key]] || 0
        racial_bonus = racial_skills[skill[:name]] || 0
        feat_bonus   = feat_skill_bonuses[skill[:name]] || 0
        equip_bonus  = equip_skill_bonuses[skill[:name]] || 0
        acp_penalty  = skill[:acp] ? total_acp : 0
        rank_bonus   = effective_rank_bonus(skill[:name], ranks_map)
        total        = ability_mod + racial_bonus + feat_bonus + equip_bonus + acp_penalty + rank_bonus

        {
          name: skill[:name],
          key_ability: skill[:key],
          trained_only: skill[:trained_only],
          ability_mod: ability_mod,
          racial_bonus: racial_bonus,
          feat_bonus: feat_bonus,
          equip_bonus: equip_bonus,
          acp_penalty: acp_penalty,
          rank_bonus: rank_bonus,
          total: total,
        }
      end
    end

    def compute_feat_skill_bonuses
      bonuses = {}
      @feats.each do |sf|
        fd = sf.feat_definition
        next unless fd

        (fd.effects || []).each do |effect|
          next unless effect["type"] == "skill_bonus"

          target = effect["skill"]
          target = sf.choice if target == "chosen skill" && sf.choice.present?
          next if target.blank?

          bonuses[target] = (bonuses[target] || 0) + (effect["bonus"] || 0)
        end
      end
      bonuses
    end

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

    def skill_ranks_raw
      raw = @src.try(:skill_ranks)
      return {} unless raw.is_a?(Hash)
      raw.transform_keys(&:to_s).transform_values { |v| v.to_i }
    end

    def effective_rank_bonus(skill_name, ranks_map)
      cid   = @src.character_class
      level = @src.level.to_i
      level = 1 if level < 1
      cap   = max_ranks_cap(skill_name, cid, level)
      ranks_map.fetch(skill_name, 0).clamp(0, cap)
    end

    def max_ranks_cap(skill_name, class_id, level)
      per_level_cap = level + 3
      return (per_level_cap / 2) if class_id.blank?

      list     = ClassSkillsData::LISTS[class_id]
      is_class = list&.include?(skill_name)
      is_class ? per_level_cap : (per_level_cap / 2)
    end
  end
end
