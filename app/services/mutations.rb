# frozen_string_literal: true

module Mutations
  private

  def apply_mutations(mutations)
    return [] unless mutations.is_a?(Hash)

    mutations = mutations.deep_symbolize_keys
    lines = []
    ActionEconomySync.apply!(mutations, adventure: @adventure, log: @log)
    BattlefieldSync.apply!(mutations, adventure: @adventure, log: @log)
    lines.concat(Array(PlayerMutations.new(sheet: @sheet, adventure: @adventure, config: @config, log: @log).call(mutations[:player])))
    lines.concat(Array(NpcMutations.new(adventure: @adventure, log: @log).call(mutations[:npcs])))
    lines.concat(Array(InventoryMutations.new(
      adventure: @adventure,
      sheet: @sheet,
      log: @log,
      on_error: ->(step, err) { pipeline_error!(step, err) }
    ).call(mutations[:inventory])))
    @on_sheet_update&.call
    lines
  end

  def apply_player_mutations(player_muts)
    PlayerMutations.new(sheet: @sheet, adventure: @adventure, config: @config, log: @log).call(player_muts)
  end

  def apply_npc_mutations(npc_muts)
    NpcMutations.new(adventure: @adventure, log: @log).call(npc_muts)
  end
end
