# frozen_string_literal: true

module Combat
  module Resolvers
    # Self-heal spell-cast resolver mixed into Combat::PlayerActionResolver.
    # Rolls the spell's healing dice (caster-level bonus already baked
    # in by HealOptionBuilder), applies the HP delta to the player
    # capped at max_hp, decrements the action economy.
    module Heal
      private

      def resolve_heal
        spell_id = lookup_heal_spell_id!
        option = DungeonMaster::Combat::HealOptionBuilder.resolve_option_id!(
          sheet: @sheet, adventure: @adventure, option_id: spell_id
        )

        rolled = DungeonMaster::Rolls::CombatDice.roll_damage_expression(option[:dice].to_s)
        hp_before = @sheet.hp.to_i
        hp_after = [hp_before + rolled, @sheet.max_hp.to_i].min
        @sheet.update!(hp: hp_after)

        decrement_action_economy_with_delta!({ 'spend_standard' => true }, label: option[:label].to_s)

        payload = heal_payload(option, hp_before: hp_before, hp_after: hp_after, rolled: rolled)
        log_action_event!(payload)
        { status: :resolved, result: payload }
      rescue DungeonMaster::CombatMechanicResolutionError => e
        raise Combat::ResolverError.new(e.message, code: e.code || :unknown_heal_option)
      end

      def lookup_heal_spell_id!
        raw = @params[:spell_id] || @params[:attack_option_id]
        if raw.to_s.empty?
          raise Combat::ResolverError.new('spell_id is required for heal actions', code: :missing_spell_id)
        end

        raw.to_s.start_with?('spell:') ? raw.to_s : "spell:#{raw}"
      end

      def heal_payload(option, hp_before:, hp_after:, rolled:)
        healed = hp_after - hp_before
        {
          kind: 'heal',
          spell_id: option[:source_id],
          spell_name: option[:label],
          dice: option[:dice],
          rolled: rolled,
          healed: healed,
          hp_before: hp_before,
          hp_after: hp_after,
          action_cost: option[:action_cost],
          message: "#{option[:label]} heals you for #{healed} HP (#{hp_after}/#{@sheet.max_hp})."
        }
      end
    end
  end
end
