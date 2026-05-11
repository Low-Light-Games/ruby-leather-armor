# frozen_string_literal: true

module Combat
  module Movement
    module_function

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
      x_pos = npc_pos.x.to_i
      y_pos = npc_pos.y.to_i
      last_open = nil
      steps.times do
        x_pos += direction[:x]
        y_pos += direction[:y]
        break if Positions.occupied?(adventure, at_x: x_pos, at_y: y_pos, except_token_id: npc_id)

        last_open = { x: x_pos, y: y_pos }
      end
      last_open
    end
  end
end
