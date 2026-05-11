# frozen_string_literal: true

module Combat
  module Rules
    DEFAULT_REACH_SQUARES = 1
    FLANKING_BONUS = 2
    SOFT_COVER_AC_BONUS = 4

    module_function

    # @param attacker [Combat::Position]
    # @param target [Combat::Position]
    # @param allies [Array<Combat::Position>]
    # @param reach_squares [Integer]
    def flanking?(attacker:, target:, allies:, reach_squares: DEFAULT_REACH_SQUARES)
      return false unless can_flank_from?(attacker, target, reach_squares)

      mirror_x, mirror_y = mirror_square(attacker, target)
      Array(allies).any? { |ally| ally_at_mirror?(ally, attacker, target, mirror_x, mirror_y) }
    end

    # @param mover [Combat::Position]
    # @param mover_from [Combat::Position, nil]
    # @param others [Array<Combat::Position>]
    # @param default_reach_squares [Integer]
    # @return [Array<Combat::Threat>]
    def aoo_threats_against(mover:, mover_from:, others:, default_reach_squares: DEFAULT_REACH_SQUARES)
      return [] unless mover_from

      Array(others).filter_map do |other|
        next unless threatens_square?(other, mover, mover_from, default_reach_squares)

        Combat::Threat.new(position: other, reach_squares: default_reach_squares)
      end
    end

    # @param attacker [Combat::Position]
    # @param target [Combat::Position]
    # @param others [Array<Combat::Position>]
    def cover_between(attacker:, target:, others:)
      return 0 unless cover_eligible?(attacker, target)

      line = line_between(attacker, target)
      return 0 if line.length <= 1

      blocked = line.any? { |point| any_creature_blocks?(point, attacker, target, others) }
      blocked ? SOFT_COVER_AC_BONUS : 0
    end

    def cover_eligible?(attacker, target)
      attacker&.coordinates_present? && target&.coordinates_present?
    end

    def reach_for(attacker_options = {})
      reach = attacker_options[:reach_squares] || attacker_options['reach_squares']
      reach.to_i.positive? ? reach.to_i : DEFAULT_REACH_SQUARES
    end

    def threatens?(attacker:, square:, reach_squares: DEFAULT_REACH_SQUARES)
      return false unless attacker&.coordinates_present? && square.is_a?(Hash)

      [(attacker.x.to_i - square[:x].to_i).abs, (attacker.y.to_i - square[:y].to_i).abs].max <= reach_squares
    end

    def can_flank_from?(attacker, target, reach_squares)
      return false unless attacker&.coordinates_present? && target&.coordinates_present?

      attacker.distance_to(target) <= reach_squares
    end

    def mirror_square(attacker, target)
      [(2 * target.x.to_i) - attacker.x.to_i, (2 * target.y.to_i) - attacker.y.to_i]
    end

    def ally_at_mirror?(ally, attacker, target, mirror_x, mirror_y)
      return false unless ally&.coordinates_present?

      return false if [attacker.token_id, target.token_id].include?(ally.token_id)

      ally.x.to_i == mirror_x && ally.y.to_i == mirror_y
    end

    def threatens_square?(other, mover, mover_from, reach_squares)
      return false unless other&.coordinates_present?

      return false if other.token_id == mover.token_id

      chebyshev = [(other.x.to_i - mover_from.x.to_i).abs, (other.y.to_i - mover_from.y.to_i).abs].max
      chebyshev <= reach_squares
    end

    def line_between(attacker, target)
      dx = target.x.to_i - attacker.x.to_i
      dy = target.y.to_i - attacker.y.to_i
      steps = [dx.abs, dy.abs].max
      return [] if steps <= 1

      step_x = dx.to_f / steps
      step_y = dy.to_f / steps
      (1...steps).map do |i|
        { x: (attacker.x.to_i + (step_x * i)).round, y: (attacker.y.to_i + (step_y * i)).round }
      end
    end

    def any_creature_blocks?(point, attacker, target, others)
      Array(others).any? do |other|
        next false unless other&.coordinates_present?

        next false if [attacker.token_id, target.token_id].include?(other.token_id)

        other.x.to_i == point[:x] && other.y.to_i == point[:y]
      end
    end
  end
end
