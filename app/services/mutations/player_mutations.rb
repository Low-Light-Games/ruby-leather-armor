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
      return unless player_muts && @sheet

      hp_change = player_muts[:hp_change]
      if hp_change.to_i != 0
        hp_floor = @config&.instant_death? ? 0 : -@sheet.constitution
        new_hp = (@sheet.hp + hp_change.to_i).clamp(hp_floor, @sheet.max_hp)
        @sheet.update!(hp: new_hp)
      end

      conditions_changed = Conditions.apply(
        sheet: @sheet,
        add: player_muts[:conditions_add],
        remove: player_muts[:conditions_remove],
        log: @log
      )
      buff_lists = CharacterStats::BuffMutationLists.from_payload(
        buffs_add: player_muts[:buffs_add],
        buffs_remove: player_muts[:buffs_remove],
        log: @log
      )
      buffs_changed = @buff_mutations.apply(sheet: @sheet, buff_lists: buff_lists)
      @sheet.recompute_derived_stats! if conditions_changed || buffs_changed
    end
  end
end
