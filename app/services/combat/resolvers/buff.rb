# frozen_string_literal: true

module Combat
  module Resolvers
    # Self-buff spell-cast leg of Combat::PlayerActionResolver.
    module Buff
      private

      def resolve_buff
        spell = DungeonMaster::Combat::SpellLookup.fetch!(@params[:spell_id] || @params[:attack_option_id])
        option = DungeonMaster::Combat::BuffOptionBuilder.resolve_option_id!(
          sheet: @sheet, adventure: @adventure, option_id: "spell:#{spell.id}"
        )

        rehydrate_player_sheet_after_buff!(spell)
        decrement_action_economy_with_delta!({ 'spend_standard' => true }, label: option[:label].to_s)

        payload = BuffPayload.new(option: option, spell: spell).to_h
        log_action_event!(payload)
        { status: :resolved, result: payload }
      rescue DungeonMaster::CombatMechanicResolutionError => e
        raise Combat::ResolverError.new(e.message, code: e.code || :unknown_buff_option)
      end

      def rehydrate_player_sheet_after_buff!(spell)
        buff_lists = DungeonMaster::BuffMutationLists.new(
          additions: [{ 'id' => spell.id, 'source_type' => 'spell' }],
          removals: []
        )
        changed = DungeonMaster::Mutations::BuffMutations.new(adventure: @adventure, log: buff_log_shim).apply(
          sheet: @sheet, buff_lists: buff_lists
        )
        @sheet.recompute_derived_stats! if changed
        @sheet.reload
      end

      def buff_log_shim
        @buff_log_shim ||= BuffLogShim.new
      end

      # No-op logger that satisfies the warn / info contract
      # BuffMutations expects from a pipeline Logging instance.
      class BuffLogShim
        def log!(*); end
        def play_log!(*); end
      end
    end
  end
end
