# frozen_string_literal: true

module Combat
  module Resolvers
    # Self-buff spell-cast resolver mixed into Combat::PlayerActionResolver.
    # Looks up the spell, dispatches through the existing
    # DungeonMaster::Mutations::BuffMutations pipeline (same path the AI
    # mutations use) so active_buffs / derived_stats stay consistent,
    # then decrements the action economy.
    module Buff
      private

      def resolve_buff
        spell_id = lookup_buff_spell_id!
        option = DungeonMaster::Combat::BuffOptionBuilder.resolve_option_id!(
          sheet: @sheet, adventure: @adventure, option_id: spell_id
        )
        spell = lookup_spell_definition!(option[:source_id])

        apply_buff!(spell)
        decrement_action_economy_with_delta!({ 'spend_standard' => true }, label: option[:label].to_s)

        payload = buff_payload(option, spell)
        log_action_event!(payload)
        { status: :resolved, result: payload }
      rescue DungeonMaster::CombatMechanicResolutionError => e
        raise Combat::ResolverError.new(e.message, code: e.code || :unknown_buff_option)
      end

      def lookup_buff_spell_id!
        raw = @params[:spell_id] || @params[:attack_option_id]
        if raw.to_s.empty?
          raise Combat::ResolverError.new('spell_id is required for buff actions', code: :missing_spell_id)
        end

        raw.to_s.start_with?('spell:') ? raw.to_s : "spell:#{raw}"
      end

      def lookup_spell_definition!(source_id)
        spell = SpellDefinition.find_by(id: source_id)
        return spell if spell

        raise Combat::ResolverError.new("spell not found: #{source_id.inspect}", code: :spell_not_found)
      end

      def apply_buff!(spell)
        buff_lists = DungeonMaster::BuffMutationLists.new(
          additions: [{ 'id' => spell.id, 'source_type' => 'spell' }],
          removals: []
        )
        DungeonMaster::Mutations::BuffMutations.new(adventure: @adventure, log: buff_log_shim).apply(
          sheet: @sheet, buff_lists: buff_lists
        )
        @sheet.reload
      end

      def buff_payload(option, spell)
        {
          kind: 'buff',
          spell_id: spell.id,
          spell_name: spell.name,
          duration: spell.duration,
          summary: spell.summary,
          action_cost: option[:action_cost],
          message: "#{spell.name} active — #{spell.summary}"
        }
      end

      # Combat::PlayerActionResolver doesn't carry a Logging instance the
      # way the AI pipeline does — give BuffMutations a no-op shim for
      # the warn / info calls it makes when active_buffs change.
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
