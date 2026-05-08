# frozen_string_literal: true

module Combat
  class Context
    def self.build(ctx, participants:, **overrides)
      hash = {
        "active"        => ctx["active"],
        "round"         => ctx["round"],
        "current_turn"  => ctx["current_turn"],
        "turn_order"    => ctx["turn_order"],
        "participants"  => participants,
        "terrain_notes" => ctx["terrain_notes"]
      }.merge(overrides.transform_keys(&:to_s))
      hash["battlefield_ref"]      = ctx["battlefield_ref"]      if ctx["battlefield_ref"].present?
      hash["last_battlefield_ref"] = ctx["last_battlefield_ref"] if ctx["last_battlefield_ref"].present?
      hash
    end

    def self.pending(participants:, round: 1, current_turn: nil, turn_order: nil, terrain_notes: nil)
      {
        "active" => false,
        "round" => round,
        "current_turn" => current_turn,
        "turn_order" => Array(turn_order),
        "participants" => participants,
        "terrain_notes" => terrain_notes
      }
    end
  end
end
