# frozen_string_literal: true

module Combat
  module Resolvers
    # End-turn resolution for Combat::PlayerActionResolver. Mixed in to
    # keep the dispatcher class small.
    #
    # PR-B intentionally skips NPC actions on end-turn; the
    # deterministic NPC turn engine (Combat::NpcTurn) lands in PR-F.
    # Until then we cycle the round counter, reseed the player's action
    # economy, and log a row noting that NPCs were skipped so play
    # history makes sense.
    module EndTurn
      private

      def resolve_end_turn
        ctx = @adventure.combat_context.deep_dup.deep_stringify_keys
        next_round = ctx['round'].to_i.then { |r| [r, 1].max + 1 }
        player = Combat::PlayerActionResolver::PLAYER_NAME

        ApplicationRecord.transaction do
          ctx['round'] = next_round
          ctx['current_turn'] = player
          ctx['action_economy'] = DungeonMaster::Battlefield::ActionEconomy
                                  .build_for_turn_holder(player, combat_ctx: ctx)
          @adventure.update!(combat_context: ctx)
        end

        payload = end_turn_payload(next_round)
        log_action_event!(payload)
        { status: :resolved, result: payload }
      end

      def end_turn_payload(next_round)
        {
          kind: 'end_turn',
          round_advanced_to: next_round,
          npc_actions_skipped: true,
          message: "Turn ended. Round #{next_round} begins. " \
                   '(NPC actions are deterministic in PR-F; none ran this round.)'
        }
      end
    end
  end
end
