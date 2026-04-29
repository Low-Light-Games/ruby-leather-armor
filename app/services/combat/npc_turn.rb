# frozen_string_literal: true

module Combat
  # Deterministic engine for one NPC's combat turn (PR-F of the
  # combat-determinism arc — see docs/combat_redesign.md). Walks the
  # creature's ProgrammedBehavior and the grid to pick:
  #
  #   1. The first preferred attack whose engagement range matches the
  #      current distance to the player.
  #   2. If no attack matches and approach_when_out_of_reach is true,
  #      step toward the player up to the creature's speed and pick the
  #      best attack from the new position.
  #   3. If HP fraction is at or below morale.flee_at_hp_pct, step
  #      directly away from the player instead of attacking.
  #
  # Returns an array of NpcTurnEvent records (move, attack, flee, skip)
  # suitable for serialization back to the HUD.
  module NpcTurn
    DEFAULT_NPC_SPEED_SQUARES = 6

    module_function

    # @param creature [CreatureSheet]
    # @param adventure [Adventure]
    # @param target_sheet [AdventureSheet]
    # @return [Array<Hash>] events; each has :kind and a :payload
    def call(creature:, adventure:, target_sheet:)
      return [skip_event(creature, 'creature is down')] if creature.hp.to_i <= 0

      policy = ProgrammedBehavior.for(creature)
      npc_pos = Positions.position_for_creature_sheet(adventure, creature.id)
      target_pos = Positions.player_position(adventure)

      unless npc_pos&.coordinates_present? && target_pos&.coordinates_present?
        return [skip_event(creature,
                           'no canonical positions')]
      end

      ctx = NpcTurnContext.new(
        actors: { creature: creature, target_sheet: target_sheet, policy: policy },
        world: { adventure: adventure, npc_pos: npc_pos, target_pos: target_pos }
      )
      return [flee_event(ctx)] if should_flee?(creature, policy)

      execute_attack_or_approach(ctx)
    end

    def execute_attack_or_approach(ctx)
      distance = ctx.npc_pos.distance_to(ctx.target_pos)
      attack_pref = ctx.policy.preferred_attacks.find { |p| p.matches_distance?(distance) }

      if attack_pref
        [attack_event(creature: ctx.creature, target_sheet: ctx.target_sheet, attack_pref: attack_pref)]
      elsif ctx.policy.approach_when_out_of_reach?
        approach_then_attack(ctx)
      else
        [skip_event(ctx.creature, 'no attack matches current range; approach disabled')]
      end
    end

    def approach_then_attack(ctx)
      events = []
      step = best_approach_step(ctx)
      if step
        npc_id = npc_token_id_for(ctx.creature)
        Positions.move_token!(ctx.adventure, token_id: npc_id, at_x: step[:x], at_y: step[:y])
        events << move_event(ctx.creature, from: { x: ctx.npc_pos.x.to_i, y: ctx.npc_pos.y.to_i }, to: step)
      end

      events << post_approach_action(ctx)
      events
    end

    def best_approach_step(ctx)
      speed = npc_speed_squares(ctx.creature)
      npc_id = npc_token_id_for(ctx.creature)
      inputs = FlankApproach::Inputs.new(
        adventure: ctx.adventure, npc_pos: ctx.npc_pos, target_pos: ctx.target_pos,
        self_creature: ctx.creature, speed: speed
      )
      destination = FlankApproach.preferred_destination(inputs)
      if destination
        FlankApproach.walk_toward(adventure: ctx.adventure, start_pos: ctx.npc_pos,
                                  destination: destination, speed: speed, npc_id: npc_id)
      else
        approach_step(npc_pos: ctx.npc_pos, target_pos: ctx.target_pos, speed: speed,
                      adventure: ctx.adventure, npc_id: npc_id)
      end
    end

    def post_approach_action(ctx)
      new_pos = Positions.position_for_creature_sheet(ctx.adventure, ctx.creature.id)
      new_distance = new_pos.distance_to(ctx.target_pos)
      attack_pref = ctx.policy.preferred_attacks.find { |p| p.matches_distance?(new_distance) }
      if attack_pref
        attack_event(creature: ctx.creature, target_sheet: ctx.target_sheet, attack_pref: attack_pref)
      else
        skip_event(ctx.creature, "still out of reach after moving (#{new_distance} sq)")
      end
    end

    def attack_event(creature:, target_sheet:, attack_pref:)
      outcome = NpcAttackResolver.call(
        attacker: creature, target_sheet: target_sheet,
        target_kind: :player, attack_pref: attack_pref
      )
      NpcTurnEvent::Attack.new(creature: creature, attack_pref: attack_pref, outcome: outcome).to_h
    end

    def move_event(creature, from:, to:)
      NpcTurnEvent::Move.new(creature: creature, from: from, to: to).to_h
    end

    def skip_event(creature, reason)
      NpcTurnEvent::Skip.new(creature: creature, reason: reason).to_h
    end

    def flee_event(ctx)
      creature = ctx.creature
      adventure = ctx.adventure
      npc_pos = ctx.npc_pos
      retreat = retreat_step(npc_pos: npc_pos, target_pos: ctx.target_pos,
                             speed: npc_speed_squares(creature),
                             adventure: adventure, npc_id: npc_token_id_for(creature))
      return skip_event(creature, 'wants to flee but is cornered') unless retreat

      Positions.move_token!(adventure, token_id: npc_token_id_for(creature),
                                       at_x: retreat[:x], at_y: retreat[:y])
      NpcTurnEvent::Flee.new(
        creature: creature,
        from: { x: npc_pos.x.to_i, y: npc_pos.y.to_i },
        to: retreat
      ).to_h
    end

    # ── helpers ──────────────────────────────────────────────────────

    def should_flee?(creature, policy)
      threshold = policy.flee_at_hp_pct
      return false unless threshold.positive?

      max = creature.max_hp.to_i
      return false if max.zero?

      (creature.hp.to_f / max) <= threshold
    end

    def npc_speed_squares(creature)
      stats = creature.derived_stats || {}
      speed_feet = stats['speed'] || stats[:speed]
      return DEFAULT_NPC_SPEED_SQUARES if speed_feet.to_i.zero?

      (speed_feet.to_i / Positions::SQUARE_FEET).clamp(1, 30)
    end

    def npc_token_id_for(creature)
      "creature_#{creature.id}"
    end

    # Approach/retreat walkers extracted to Combat::Movement so the
    # module stays under the length cap.
    def approach_step(**) = Movement.approach_step(**)
    def retreat_step(**)  = Movement.retreat_step(**)
  end
end
