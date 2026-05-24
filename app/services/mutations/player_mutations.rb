# frozen_string_literal: true

module Mutations
  class PlayerMutations
    def initialize(sheet:, adventure:, config:, log:)
      @sheet = sheet
      @config = config
      @log = log
      @buff_mutations = CharacterStats::BuffMutations.new(adventure: adventure, log: log)
    end

    def call(player_muts)
      return [] unless player_muts && @sheet

      lines = []

      hp_change = player_muts[:hp_change]
      if hp_change.to_i != 0
        old_hp = @sheet.hp
        hp_floor = @config&.instant_death? ? 0 : -@sheet.constitution
        new_hp = (old_hp + hp_change.to_i).clamp(hp_floor, @sheet.max_hp)
        @sheet.update!(hp: new_hp)
        lines << "HP: #{old_hp} → #{new_hp} (#{new_hp >= old_hp ? '+' : ''}#{new_hp - old_hp})" if new_hp != old_hp
      end

      conditions_before = Array(@sheet.conditions).dup
      conditions_changed = Conditions.apply(
        sheet: @sheet,
        add: player_muts[:conditions_add],
        remove: player_muts[:conditions_remove],
        log: @log
      )
      if conditions_changed
        conditions_after = Array(@sheet.conditions)
        (conditions_after - conditions_before).each { |c| lines << "Condition gained: #{c}" }
        (conditions_before - conditions_after).each { |c| lines << "Condition removed: #{c}" }
      end

      buffs_before = buff_source_names(@sheet.active_buffs)
      buff_lists = CharacterStats::BuffMutationLists.from_payload(
        buffs_add: player_muts[:buffs_add],
        buffs_remove: player_muts[:buffs_remove],
        log: @log
      )
      buffs_changed = @buff_mutations.apply(sheet: @sheet, buff_lists: buff_lists)
      if buffs_changed
        buffs_after = buff_source_names(@sheet.active_buffs)
        (buffs_after - buffs_before).each { |name| lines << "Buff gained: #{name}" }
        (buffs_before - buffs_after).each { |name| lines << "Buff ended: #{name}" }
      end

      @sheet.recompute_derived_stats! if conditions_changed || buffs_changed
      lines
    end

    private

    def buff_source_names(buffs)
      Array(buffs).filter_map { |b| b["source"].presence || b[:source].presence }
    end
  end
end
