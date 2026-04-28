# frozen_string_literal: true

module Combat
  module Resolvers
    # Move + withdraw + 5-foot step resolution. Mixed into
    # Combat::PlayerActionResolver. The grid is canonical for positions
    # (PR-C); rules engine answers AoO threats (PR-D); withdraw skips
    # the departure-square AoO and costs a full round.
    module Move
      MOVE_MODES_WITHOUT_AOO = ['5-foot step', 'withdraw'].freeze

      private

      def resolve_move
        plan = build_move_plan!
        battlefield = commit_move!(plan)
        emit_move_payload(plan, battlefield)
      end

      def build_move_plan!
        target_x, target_y = lookup_move_coordinates!
        withdraw_requested = truthy?(@params[:withdraw])
        origin = lookup_player_origin!
        ensure_move_is_legal!(origin, target_x, target_y)

        distance = chebyshev_distance(origin, target_x, target_y)
        ensure_within_speed!(distance)

        delta, mode = movement_cost_delta(distance, withdraw: withdraw_requested)
        aoo_outcomes = aoo_outcomes_for(mode, origin)

        {
          origin: origin, target_x: target_x, target_y: target_y,
          distance: distance, delta: delta, mode: mode, aoo_outcomes: aoo_outcomes
        }
      end

      def lookup_move_coordinates!
        x = @params[:x]
        y = @params[:y]
        raise Combat::ResolverError.new('x and y are required', code: :missing_coordinates) if x.nil? || y.nil?

        [x.to_i, y.to_i]
      end

      def lookup_player_origin!
        origin = Combat::Positions.player_position(@adventure)
        return origin if origin&.coordinates_present?

        raise Combat::ResolverError.new('player has no canonical position on the battlefield',
                                        code: :missing_player_position)
      end

      def ensure_move_is_legal!(origin, target_x, target_y)
        if origin.x.to_i == target_x && origin.y.to_i == target_y
          raise Combat::ResolverError.new('player is already on that square', code: :no_op_move)
        end

        return unless Combat::Positions.occupied?(@adventure, at_x: target_x, at_y: target_y,

                                                              except_token_id: Combat::Positions::PLAYER_TOKEN_ID)

        raise Combat::ResolverError.new('target square is occupied', code: :square_occupied)
      end

      def chebyshev_distance(origin, target_x, target_y)
        [(origin.x.to_i - target_x).abs, (origin.y.to_i - target_y).abs].max
      end

      def ensure_within_speed!(distance)
        speed_squares = Combat::Positions.speed_squares_for(@sheet)
        return if distance <= speed_squares

        raise Combat::ResolverError.new("target is #{distance} squares away — speed allows up to #{speed_squares}",
                                        code: :out_of_reach)
      end

      def truthy?(value)
        value == true || value.to_s == 'true'
      end

      # Withdraw is the only mode whose departure square does NOT provoke.
      # Standard move provokes from the departure square. 5-foot step
      # never provokes.
      def aoo_outcomes_for(mode, origin)
        return [] if MOVE_MODES_WITHOUT_AOO.include?(mode)

        resolve_aoo_against_player(origin)
      end

      def resolve_aoo_against_player(origin)
        others = Combat::Positions.for_adventure(@adventure)
                                  .reject { |p| p.token_id == Combat::Positions::PLAYER_TOKEN_ID }
        threats = Combat::Rules.aoo_threats_against(mover: origin, mover_from: origin, others: others)
        return [] if threats.empty?

        threats.filter_map { |threat| resolve_single_aoo(threat) }
      end

      def resolve_single_aoo(threat)
        creature = creature_for_position(threat.position)
        return nil unless creature && creature.hp.to_i.positive?

        Combat::NpcAttackResolver.call(attacker: creature, target_sheet: @sheet, target_kind: :player)
      end

      def creature_for_position(position)
        sid = position.creature_sheet_id
        return nil if sid.blank?

        @adventure.creature_sheets.find_by(id: sid.to_i)
      end

      def commit_move!(plan)
        battlefield = nil
        ApplicationRecord.transaction do
          battlefield = Combat::Positions.move_player_token!(@adventure, at_x: plan[:target_x], at_y: plan[:target_y])
          decrement_action_economy_with_delta!(plan[:delta], label: "#{plan[:mode]} (#{plan[:distance]} squares)")
        end
        battlefield
      end

      def emit_move_payload(plan, battlefield)
        payload = Combat::MoveResolutionPayload.new(
          origin: plan[:origin],
          destination: { x: plan[:target_x], y: plan[:target_y] },
          movement: { distance: plan[:distance], mode: plan[:mode], battlefield_version: battlefield&.version },
          aoo_outcomes: plan[:aoo_outcomes]
        ).to_h
        log_action_event!(payload)
        { status: :resolved, result: payload }
      end

      # Three movement modes:
      #
      #   * 5-foot step — 1 square; legal as long as the move slot has
      #     not been spent this round and no full-round action was
      #     claimed. The standard action does NOT need to still be
      #     available — textbook PF1e lets a character 5-ft step after
      #     a standard attack. Never provokes; spends the move slot.
      #   * withdraw    — full-round; departure square does NOT provoke
      #     (textbook PF1e safe-retreat); requires both standard and
      #     move unspent so spend_full_round can claim them together.
      #   * move        — anything else; standard provoke from the
      #     departure square.
      def movement_cost_delta(distance, withdraw: false)
        econ = (@adventure.combat_context || {})['action_economy'] || {}
        return withdraw_delta!(econ) if withdraw

        return [{ 'spend_move' => true }, '5-foot step'] if can_5ft_step?(distance, econ)
        return [{ 'spend_move' => true }, 'move'] if econ['move_available'] == true

        raise Combat::ResolverError.new('no move action available this turn', code: :no_move_available)
      end

      def withdraw_delta!(econ)
        unless full_round_available?(econ)
          raise Combat::ResolverError.new('withdraw requires both standard and move actions unspent',
                                          code: :withdraw_unavailable)
        end

        [{ 'spend_full_round' => true }, 'withdraw']
      end

      def full_round_available?(econ)
        econ['standard_available'] == true &&
          econ['move_available'] == true &&
          econ['full_round_claimed'] != true
      end

      def can_5ft_step?(distance, econ)
        distance == 1 &&
          econ['move_available'] == true &&
          econ['full_round_claimed'] != true
      end
    end
  end
end
