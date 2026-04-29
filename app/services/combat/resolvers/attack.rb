# frozen_string_literal: true

module Combat
  module Resolvers
    # Attack resolution for Combat::PlayerActionResolver. Mixed in so
    # the dispatcher class stays small. Reads @adventure, @sheet,
    # @user, @params, @submitted_dice from the includer. Lookups,
    # dice, and the response payload live in dedicated sibling modules
    # so this one stays focused on the resolve_attack flow.
    module Attack
      def self.included(base)
        base.include(Combat::Resolvers::AttackLookups)
        base.include(Combat::Resolvers::AttackDice)
      end

      private

      def resolve_attack
        inputs = build_attack_inputs!

        return awaiting_player_dice(inputs: inputs) if @submitted_dice.nil? && client_dice?

        attack = roll_player_attack(inputs[:attack_bonus], inputs[:defense_dc])
        damage = roll_player_damage(inputs[:option], attack[:hit])

        apply_attack_resolution(
          inputs: inputs,
          outcome: { attack: attack, damage: damage }
        )
      end

      # Bundled resolver-input record. Computed once at the top of
      # resolve_attack and threaded through the rest of the flow so the
      # individual helpers stay under the parameter-list cap.
      def build_attack_inputs!
        option = lookup_attack_option!
        target = lookup_target!
        ensure_target_in_reach!(option, target)
        situational = situational_modifiers_for(option, target)
        attack_bonus = attack_bonus_for(option) + situational[:flanking_bonus]
        defense_dc = defense_dc_for(target, option) + situational[:cover_bonus]

        {
          option: option, target: target,
          attack_bonus: attack_bonus, defense_dc: defense_dc,
          situational: situational
        }
      end

      # Refuse melee/melee_touch attacks against targets outside reach. Ranged
      # modes are unrestricted here. When either combatant has no grid position
      # (e.g. legacy combats started before the battlefield grid existed) we
      # skip the check rather than blocking — the attack just resolves like
      # before.
      def ensure_target_in_reach!(option, target)
        return if ranged_mode?(option[:attack_mode])

        creature = target.first
        attacker_pos = Combat::Positions.player_position(@adventure)
        target_pos = Combat::Positions.position_for_creature_sheet(@adventure, creature.id)
        return unless attacker_pos&.coordinates_present? && target_pos&.coordinates_present?

        reach = Combat::Rules.reach_for(option)
        distance = attacker_pos.distance_to(target_pos)
        return if distance <= reach

        raise Combat::ResolverError.new(
          "#{creature.name} is out of melee reach (#{distance} squares away, reach #{reach}). Move closer first.",
          code: :target_out_of_reach
        )
      end

      def situational_modifiers_for(option, target)
        creature = target.first
        attacker_pos = Combat::Positions.player_position(@adventure)
        target_pos = Combat::Positions.position_for_creature_sheet(@adventure, creature.id)
        return zero_situational unless attacker_pos&.coordinates_present? && target_pos&.coordinates_present?

        others = Combat::Positions.for_adventure(@adventure)
        reach = Combat::Rules.reach_for(option)
        flanking = Combat::Rules.flanking?(attacker: attacker_pos, target: target_pos,
                                           allies: others, reach_squares: reach)
        cover = Combat::Rules.cover_between(attacker: attacker_pos, target: target_pos, others: others)

        situational_payload(flanking: flanking, cover: cover)
      end

      def situational_payload(flanking:, cover:)
        {
          flanking: flanking,
          flanking_bonus: flanking ? Combat::Rules::FLANKING_BONUS : 0,
          cover: cover,
          cover_bonus: cover
        }
      end

      def zero_situational
        situational_payload(flanking: false, cover: 0)
      end

      def apply_attack_resolution(inputs:, outcome:)
        creature, target_name = inputs[:target]
        target_state = apply_attack_damage(creature, outcome[:attack][:hit], outcome[:damage][:total])
        decrement_action_economy_for(inputs[:option])

        payload = Combat::AttackResolutionPayload.new(
          attack_input: { option: inputs[:option], target_name: target_name,
                          attack_bonus: inputs[:attack_bonus], defense_dc: inputs[:defense_dc] },
          attack_outcome: { attack: outcome[:attack], damage: outcome[:damage], target_state: target_state },
          situational: inputs[:situational]
        ).to_h
        log_action_event!(payload)
        { status: :resolved, result: payload }
      end

      def apply_attack_damage(creature, hit, damage_total)
        hp_before = creature.hp.to_i
        hp_after = hp_before
        target_dropped = false

        if hit && damage_total
          hp_after = (hp_before - damage_total).clamp(0, creature.max_hp.to_i)
          creature.update!(hp: hp_after)
          target_dropped = hp_after <= 0
        end

        { hp_before: hp_before, hp_after: hp_after, dropped: target_dropped }
      end

      def decrement_action_economy_for(option)
        ApplicationRecord.transaction do
          decrement_action_economy_with_delta!(action_cost_delta(option), label: option[:label].to_s)
        end
      end

      def action_cost_delta(option)
        case option[:action_cost].to_s
        when 'full_round' then { 'spend_full_round' => true }
        when 'move'       then { 'spend_move' => true }
        when 'swift'      then { 'spend_swift' => true }
        else                   { 'spend_standard' => true }
        end
      end

      def awaiting_player_dice(inputs:)
        creature, target_name = inputs[:target]
        { status: :awaiting_player_dice,
          request: pending_request(creature: creature, target_name: target_name, inputs: inputs) }
      end

      def pending_request(creature:, target_name:, inputs:)
        option = inputs[:option]
        situational = inputs[:situational]
        {
          kind: 'attack',
          attack_option_id: option[:id].to_s,
          attack_label: option[:label].to_s,
          target_name: target_name,
          target_creature_sheet_id: creature.id,
          attack_bonus: inputs[:attack_bonus],
          defense_dc: inputs[:defense_dc],
          defense_kind: option[:defense_kind],
          damage_expression: option[:damage],
          damage_type: option[:damage_type],
          damage_ability_bonus: damage_ability_bonus(option),
          flanking: situational[:flanking],
          flanking_bonus: situational[:flanking_bonus],
          cover_bonus: situational[:cover_bonus]
        }
      end

      def client_dice?
        @user&.combat_dice_strategy.to_s == 'client'
      end
    end
  end
end
