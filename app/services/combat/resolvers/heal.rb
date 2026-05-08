# frozen_string_literal: true

module Combat
  module Resolvers
    module Heal
      private

      def resolve_heal
        spell = Combat::Options::SpellLookup.fetch!(@params[:spell_id] || @params[:attack_option_id])
        option = Combat::Options::HealOptionBuilder.resolve_option_id!(
          sheet: @sheet, adventure: @adventure, option_id: "spell:#{spell.id}"
        )

        rolled = Combat::Dice.roll_damage_expression(option[:dice].to_s)
        hp_before = @sheet.hp.to_i
        hp_after = [hp_before + rolled, @sheet.max_hp.to_i].min
        @sheet.update!(hp: hp_after)
        decrement_action_economy_with_delta!({ 'spend_standard' => true }, label: option[:label].to_s)

        payload = HealPayload.new(
          option: option, hp_before: hp_before, hp_after: hp_after, max_hp: @sheet.max_hp, rolled: rolled
        ).to_h
        log_action_event!(payload)
        Combat::EventLog.write!(adventure: @adventure, content: payload[:message], user: @user)
        { status: :resolved, result: payload }
      rescue Combat::MechanicResolutionError => e
        raise Combat::ResolverError.new(e.message, code: e.code || :unknown_heal_option)
      end
    end
  end
end
