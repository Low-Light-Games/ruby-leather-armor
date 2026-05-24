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
    persist_mutation_lines!(lines)
    lines
  end

  def apply_player_mutations(player_muts)
    lines = Array(PlayerMutations.new(sheet: @sheet, adventure: @adventure, config: @config, log: @log).call(player_muts))
    persist_mutation_lines!(lines)
    lines
  end

  def apply_npc_mutations(npc_muts)
    lines = Array(NpcMutations.new(adventure: @adventure, log: @log).call(npc_muts))
    persist_mutation_lines!(lines)
    lines
  end

  def persist_mutation_lines!(lines)
    return if lines.empty?
    return unless @log&.registry_entry_uuid.present?

    metadata = { "registry_entry_uuid" => @log.registry_entry_uuid }
    lines.each do |line|
      begin
        msg = @adventure.adventure_messages.create!(
          role: "dm", content: line, message_type: "action_result", metadata: metadata
        )
        AdventureChannel.broadcast_to(
          @adventure,
          type: "pipeline_action_result",
          messages: [Adventures::MessageSerializer.as_json(msg, admin: @user&.admin?)]
        )
      rescue StandardError => e
        @log&.log!(:warn, "[Mutations] Failed to persist mutation line: #{e.message}")
      end
    end
  end
end
