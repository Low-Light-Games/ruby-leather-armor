# frozen_string_literal: true

module Combat
  # Pure deterministic PF1e rules over Combat::Positions (PR-D of the
  # combat-determinism arc — see docs/combat_redesign.md). Code answers
  # "is X flanked?", "what NPCs threaten Y?", "is there cover between A
  # and B?" — no AI involvement, no I/O.
  #
  # Coordinate space follows Combat::Positions: integer (x, y) with
  # Chebyshev distance (every diagonal counts as 1 square). Reach is
  # measured in squares, default 1 for natural / one-handed weapons.
  # Reach weapons + larger creatures will need an opt-in `reach` arg
  # surfaced from the attack option / creature stat block — this v1
  # only knows the default.
  #
  # Cover modeling is intentionally minimal until the world layer
  # (battlefield.world.cells) actually carries cover terrain. For now,
  # `cover_between` returns 0 unless an intervening *creature* sits
  # between attacker and target on the orthogonal/diagonal line — the
  # only cover source code can derive without terrain data.
  module Rules
    DEFAULT_REACH_SQUARES = 1
    FLANKING_BONUS = 2
    SOFT_COVER_AC_BONUS = 4

    Threat = Struct.new(:position, :reach_squares, keyword_init: true)

    module_function

    # PF1e flanking: two allies of the attacker threaten the same target
    # from directly opposite sides (the line through the target's square
    # passes through both attacker squares). For PR-D v1 the only "ally"
    # of the player is implicit — we treat any other non-target combatant
    # threatening the target's square from the opposite side as a flanking
    # partner. Helpful in the typical "you flank with the goblin you're
    # fighting alongside" scenario; the long-tail of who-counts-as-an-ally
    # waits for character-relationships modeling.
    def flanking?(attacker:, target:, allies:, reach_squares: DEFAULT_REACH_SQUARES)
      return false unless attacker&.coordinates_present? && target&.coordinates_present?
      return false unless attacker.distance_to(target) <= reach_squares

      ax = attacker.x.to_i
      ay = attacker.y.to_i
      tx = target.x.to_i
      ty = target.y.to_i
      mirror_x = (2 * tx) - ax
      mirror_y = (2 * ty) - ay

      Array(allies).any? do |ally|
        next false unless ally&.coordinates_present?
        next false if ally.token_id == attacker.token_id
        next false if ally.token_id == target.token_id

        ally.x.to_i == mirror_x && ally.y.to_i == mirror_y
      end
    end

    # Returns the attackers (positions) that threaten +mover_from+ — i.e.
    # whose reach covers that square — and would get a free swing if
    # +mover_from+ leaves it. Caller filters by friend/foe; the rules
    # engine doesn't know factions yet.
    def aoo_threats_against(mover:, mover_from:, others:, default_reach_squares: DEFAULT_REACH_SQUARES)
      return [] unless mover_from
      Array(others).filter_map do |other|
        next unless other&.coordinates_present?
        next if other.token_id == mover.token_id

        reach = default_reach_squares
        chebyshev = [(other.x.to_i - mover_from.x.to_i).abs, (other.y.to_i - mover_from.y.to_i).abs].max
        next if chebyshev > reach

        Threat.new(position: other, reach_squares: reach)
      end
    end

    # Soft cover only — terrain cover lands when world.cells carries
    # cover types. An intervening creature on the straight line (or
    # diagonal) between attacker and target grants +4 AC to the target.
    def cover_between(attacker:, target:, others:)
      return 0 unless attacker&.coordinates_present? && target&.coordinates_present?

      ax = attacker.x.to_i
      ay = attacker.y.to_i
      tx = target.x.to_i
      ty = target.y.to_i
      dx = tx - ax
      dy = ty - ay

      # Adjacent squares can't have intervening cover.
      return 0 if [dx.abs, dy.abs].max <= 1

      steps = [dx.abs, dy.abs].max
      step_x = steps.zero? ? 0 : (dx.to_f / steps)
      step_y = steps.zero? ? 0 : (dy.to_f / steps)

      blocking = (1...steps).any? do |i|
        ix = (ax + (step_x * i)).round
        iy = (ay + (step_y * i)).round
        Array(others).any? do |o|
          next false unless o&.coordinates_present?
          next false if o.token_id == attacker.token_id
          next false if o.token_id == target.token_id

          o.x.to_i == ix && o.y.to_i == iy
        end
      end

      blocking ? SOFT_COVER_AC_BONUS : 0
    end

    def reach_for(attacker_options = {})
      reach = attacker_options[:reach_squares] || attacker_options['reach_squares']
      reach.to_i.positive? ? reach.to_i : DEFAULT_REACH_SQUARES
    end

    def threatens?(attacker:, square:, reach_squares: DEFAULT_REACH_SQUARES)
      return false unless attacker&.coordinates_present?
      return false unless square.is_a?(Hash)

      [(attacker.x.to_i - square[:x].to_i).abs, (attacker.y.to_i - square[:y].to_i).abs].max <= reach_squares
    end
  end
end
