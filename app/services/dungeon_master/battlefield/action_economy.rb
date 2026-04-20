# frozen_string_literal: true

module DungeonMaster
  module Battlefield
    # PF1e-style turn pool in combat_context["action_economy"] (BETA — simplified slots).
    module ActionEconomy
      module_function

      class TurnState
        attr_reader :round, :holder

        def initialize(round:, holder:)
          @round = round.to_i
          @holder = holder.to_s
        end

        def to_h
          {
            "round" => round,
            "holder" => holder,
            "standard_available" => true,
            "move_available" => true,
            "swift_available" => true,
            "full_round_claimed" => false
          }
        end
      end

      def build_for_turn_holder(holder_name, combat_ctx:)
        TurnState.new(round: combat_ctx["round"], holder: holder_name).to_h
      end

      # @param delta [Hash] string keys: spend_standard, spend_move, spend_swift, refund_* (bool)
      # @return [Hash] merged economy or raises ArgumentError
      def apply_delta!(economy, delta)
        econ = (economy || {}).deep_stringify_keys
        d = (delta || {}).deep_stringify_keys
        out = econ.dup

        if truthy?(d["spend_standard"])
          raise ArgumentError, "standard action unavailable" unless truthy?(out["standard_available"])
          out["standard_available"] = false
        end
        if truthy?(d["spend_move"])
          raise ArgumentError, "move action unavailable" unless truthy?(out["move_available"])
          out["move_available"] = false
        end
        if truthy?(d["spend_swift"])
          raise ArgumentError, "swift action unavailable" unless truthy?(out["swift_available"])
          out["swift_available"] = false
        end
        if truthy?(d["spend_full_round"])
          raise ArgumentError, "full-round already claimed" if truthy?(out["full_round_claimed"])
          unless truthy?(out["standard_available"]) && truthy?(out["move_available"])
            raise ArgumentError, "full-round requires both standard and move actions to still be available"
          end
          out["full_round_claimed"] = true
          out["standard_available"] = false
          out["move_available"] = false
        end

        if truthy?(d["refund_standard"])
          out["standard_available"] = true
        end
        if truthy?(d["refund_move"])
          out["move_available"] = true
        end
        if truthy?(d["refund_swift"])
          out["swift_available"] = true
        end

        out
      end

      def truthy?(v)
        v == true || v.to_s == "true"
      end

      # UI: draw/sheath-style change — costs one move when combat rules apply.
      def equip_toggle_cost_delta
        { "spend_move" => true }
      end
    end
  end
end
