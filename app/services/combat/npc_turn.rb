# frozen_string_literal: true

module Combat
  # Deterministic engine for one NPC's combat turn (PR-F of the
  # combat-determinism arc — see docs/combat_redesign.md). Walks the
  # creature's BehaviorPolicy and the grid to pick:
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

      policy = BehaviorPolicy.new(creature.behavior_policy)
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
      approach_step(npc_pos: ctx.npc_pos, target_pos: ctx.target_pos,
                    speed: npc_speed_squares(ctx.creature),
                    adventure: ctx.adventure, npc_id: npc_token_id_for(ctx.creature))
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
      outcome = NpcAttackResolver.call(attacker: creature, target_sheet: target_sheet, target_kind: :player)
      {
        kind: 'npc_attack',
        creature_id: creature.id,
        creature_name: creature.name,
        attack_label: attack_pref.name,
        outcome: outcome.to_h
      }
    end

    def move_event(creature, from:, to:)
      {
        kind: 'npc_move',
        creature_id: creature.id,
        creature_name: creature.name,
        from: from,
        to: to,
        message: "#{creature.name} closes to (#{to[:x]}, #{to[:y]})."
      }
    end

    def skip_event(creature, reason)
      {
        kind: 'npc_skip',
        creature_id: creature.id,
        creature_name: creature.name,
        message: "#{creature.name} holds — #{reason}."
      }
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
      {
        kind: 'npc_flee',
        creature_id: creature.id,
        creature_name: creature.name,
        from: { x: npc_pos.x.to_i, y: npc_pos.y.to_i },
        to: retreat,
        message: "#{creature.name} flees to (#{retreat[:x]}, #{retreat[:y]})."
      }
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

    # Greedy single-step approach: move up to `speed` squares toward the
    # target, stopping 1 square away. Returns the destination
    # coordinates or nil if blocked.
    def approach_step(npc_pos:, target_pos:, speed:, adventure:, npc_id:)
      direction = unit_step(from: npc_pos, to: target_pos)
      max_steps = [speed, npc_pos.distance_to(target_pos) - 1].min
      return nil if max_steps <= 0

      walk_until_blocked(npc_pos: npc_pos, direction: direction, steps: max_steps,
                         adventure: adventure, npc_id: npc_id)
    end

    def retreat_step(npc_pos:, target_pos:, speed:, adventure:, npc_id:)
      direction = unit_step(from: target_pos, to: npc_pos)
      walk_until_blocked(npc_pos: npc_pos, direction: direction, steps: speed,
                         adventure: adventure, npc_id: npc_id)
    end

    def unit_step(from:, to:)
      dx = (to.x.to_i - from.x.to_i).clamp(-1, 1)
      dy = (to.y.to_i - from.y.to_i).clamp(-1, 1)
      { x: dx, y: dy }
    end

    def walk_until_blocked(npc_pos:, direction:, steps:, adventure:, npc_id:)
      x = npc_pos.x.to_i
      y = npc_pos.y.to_i
      last_open = nil
      steps.times do
        x += direction[:x]
        y += direction[:y]
        break if Positions.occupied?(adventure, at_x: x, at_y: y, except_token_id: npc_id)

        last_open = { x: x, y: y }
      end
      last_open
    end
  end
end
