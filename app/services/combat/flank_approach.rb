# frozen_string_literal: true

module Combat
  module FlankApproach
    module_function

    class Inputs
      attr_reader :adventure, :npc_pos, :target_pos, :self_creature, :speed

      def initialize(adventure:, npc_pos:, target_pos:, self_creature:, speed:)
        @adventure = adventure
        @npc_pos = npc_pos
        @target_pos = target_pos
        @self_creature = self_creature
        @speed = speed
      end

      def npc_id
        "creature_#{self_creature.id}"
      end
    end

    # @param inputs [Inputs]
    # @return [Combat::Position, nil] desired stopping square, or nil
    def preferred_destination(inputs)
      others = Positions.for_adventure(inputs.adventure)
      candidates = reachable_adjacency_squares(inputs, others)
      return nil if candidates.empty?

      best = candidates.max_by { |sq| [score(sq, inputs.target_pos, inputs.self_creature, others), -sq[:distance]] }
      Combat::Position.new(token_id: 'tmp_destination', label: 'tmp', coordinates: { x: best[:x], y: best[:y] })
    end

    def reachable_adjacency_squares(inputs, others)
      adjacency_squares(inputs.target_pos).filter_map do |sq|
        sq[:distance] = chebyshev(inputs.npc_pos, sq)
        next if sq[:distance] > inputs.speed

        next if occupied?(others, sq, except: inputs.npc_id)

        sq
      end
    end

    def walk_toward(adventure:, start_pos:, destination:, speed:, npc_id:)
      cur_x = start_pos.x.to_i
      cur_y = start_pos.y.to_i
      dest_x = destination.x.to_i
      dest_y = destination.y.to_i
      last_open = nil
      speed.times do
        break if cur_x == dest_x && cur_y == dest_y

        cur_x += (dest_x - cur_x).clamp(-1, 1)
        cur_y += (dest_y - cur_y).clamp(-1, 1)
        break if Positions.occupied?(adventure, at_x: cur_x, at_y: cur_y, except_token_id: npc_id)

        last_open = { x: cur_x, y: cur_y }
      end
      last_open
    end

    def adjacency_squares(target_pos)
      tx = target_pos.x.to_i
      ty = target_pos.y.to_i
      [-1, 0, 1].flat_map do |dx|
        [-1, 0, 1].filter_map do |dy|
          next if dx.zero? && dy.zero?

          { x: tx + dx, y: ty + dy }
        end
      end
    end

    def score(square, target_pos, self_creature, others)
      tally = 0
      tally += 5 if flanks_ally?(square, target_pos, self_creature, others)
      tally -= crowding_count(square, self_creature, others)
      tally
    end

    def flanks_ally?(square, target_pos, self_creature, others)
      mirror_x = (target_pos.x.to_i * 2) - square[:x]
      mirror_y = (target_pos.y.to_i * 2) - square[:y]
      others.any? { |pos| ally_at?(pos, self_creature, mirror_x, mirror_y) }
    end

    def crowding_count(square, self_creature, others)
      others.count { |pos| ally_adjacent_to?(pos, self_creature, square) }
    end

    def ally_at?(pos, self_creature, x_coord, y_coord)
      return false unless ally_token?(pos, self_creature)

      pos.x.to_i == x_coord && pos.y.to_i == y_coord
    end

    def ally_adjacent_to?(pos, self_creature, square)
      return false unless ally_token?(pos, self_creature)

      chebyshev_xy(pos.x.to_i, pos.y.to_i, square[:x], square[:y]) == 1
    end

    def ally_token?(pos, self_creature)
      pos.coordinates_present? && pos.actor_sheet_id.present? &&
        pos.actor_sheet_id.to_i != self_creature.id
    end

    def chebyshev(from, to)
      to_x = to.is_a?(Hash) ? to[:x] : to.x
      to_y = to.is_a?(Hash) ? to[:y] : to.y
      chebyshev_xy(from.x.to_i, from.y.to_i, to_x.to_i, to_y.to_i)
    end

    def chebyshev_xy(x_one, y_one, x_two, y_two)
      [(x_one - x_two).abs, (y_one - y_two).abs].max
    end

    def occupied?(others, square, except:)
      others.any? { |pos| occupant_at?(pos, square, except) }
    end

    def occupant_at?(pos, square, except)
      return false unless pos.coordinates_present?

      return false if pos.token_id == except

      pos.x.to_i == square[:x] && pos.y.to_i == square[:y]
    end
  end
end
