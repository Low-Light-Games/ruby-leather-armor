# frozen_string_literal: true

module Combat
  module Resolvers
    module AttackLookups
      private

      def lookup_attack_option!
        option_id = @params[:attack_option_id].to_s
        if option_id.empty?
          raise Combat::ResolverError.new('attack_option_id is required',
                                          code: :missing_attack_option_id)
        end

        Combat::Options::AttackOptionBuilder.resolve_option_id!(
          sheet: @sheet, adventure: @adventure, option_id: option_id
        )
      rescue Combat::MechanicResolutionError => e
        raise Combat::ResolverError.new(e.message, code: e.code || :unknown_attack_option)
      end

      def lookup_target!
        target_id = @params[:target_creature_sheet_id]
        if target_id.blank?
          raise Combat::ResolverError.new('target_creature_sheet_id is required',
                                          code: :missing_target)
        end

        creature = @adventure.creature_sheets.find_by(id: target_id.to_i)
        raise Combat::ResolverError.new("creature not found: id=#{target_id}", code: :target_not_found) unless creature

        if creature.hp.to_i <= 0
          raise Combat::ResolverError.new("target is already down: #{creature.name}",
                                          code: :target_down)
        end

        [creature, creature.name]
      end

      def attack_bonus_for(option)
        stats = @sheet.derived_stats || {}
        key = ranged_mode?(option[:attack_mode]) ? 'ranged_attack' : 'melee_attack'
        bonus = stats[key] || stats[key.to_sym]
        raise Combat::ResolverError.new("missing #{key} on player sheet", code: :missing_attack_bonus) if bonus.nil?

        bonus.to_i
      end

      def defense_dc_for(target, option)
        creature = target.first
        stats = creature.derived_stats || {}
        stat_key = Combat::PlayerActionResolver::DEFENSE_KIND_TO_STAT[option[:defense_kind].to_s] || 'ac'
        dc = stats[stat_key] || stats[stat_key.to_sym] || stats['ac'] || stats[:ac]
        if dc.nil?
          raise Combat::ResolverError.new("missing #{stat_key} on target derived_stats",
                                          code: :missing_defense_stat)
        end

        dc.to_i
      end
    end
  end
end
