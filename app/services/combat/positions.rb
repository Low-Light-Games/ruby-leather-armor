# frozen_string_literal: true

module Combat
  # Canonical position accessor for the combat grid (PR-C of the
  # combat-determinism arc — see docs/combat_redesign.md).
  #
  # Until this module landed, "where is X?" was answered by reading the
  # AI-narrated `combat_context` participants list — strings, not
  # coordinates. The deterministic resolver (PR-B) and the rules engine
  # (PR-D) need *coordinates* to answer flanking, AoO, cover, reach.
  # This module is the one place that translates between the
  # `adventure_battlefields.tokens` JSON shape and the combat code.
  #
  # Distance uses Chebyshev distance (max(|dx|, |dy|)) — the simplest
  # PF1e-compatible diagonal accounting where every diagonal is 1 square.
  # That diverges from canonical "alternating 1/2/1/2" diagonals, which
  # we'll model in a later iteration once the rules engine arrives in
  # PR-D and we know what corner cases actually bite us in playtest.
  module Positions
    SQUARE_FEET = 5
    PLAYER_TOKEN_ID = 'player'

    Position = Struct.new(:token_id, :label, :x, :y, :type, :creature_sheet_id, keyword_init: true) do
      def coordinates_present?
        !x.nil? && !y.nil?
      end

      def distance_to(other)
        return Float::INFINITY unless coordinates_present? && other.coordinates_present?

        [(x.to_i - other.x.to_i).abs, (y.to_i - other.y.to_i).abs].max
      end
    end

    module_function

    def for_adventure(adventure)
      battlefield = active_battlefield(adventure)
      return [] unless battlefield

      Array(battlefield.tokens).filter_map do |token_id, raw|
        next unless raw.is_a?(Hash)

        Position.new(
          token_id: token_id.to_s,
          label: raw['label'].to_s,
          x: raw['x'],
          y: raw['y'],
          type: raw['type'],
          creature_sheet_id: raw['creature_sheet_id']
        )
      end
    end

    def player_position(adventure)
      for_adventure(adventure).find { |p| p.token_id == PLAYER_TOKEN_ID }
    end

    def position_for_creature_sheet(adventure, creature_sheet_id)
      for_adventure(adventure).find { |p| p.creature_sheet_id.to_i == creature_sheet_id.to_i }
    end

    def occupied?(adventure, x:, y:, except_token_id: nil)
      for_adventure(adventure).any? do |p|
        next false unless p.coordinates_present?
        next false if p.token_id == except_token_id

        p.x.to_i == x.to_i && p.y.to_i == y.to_i
      end
    end

    def speed_squares_for(sheet)
      speed_feet = (sheet&.derived_stats || {})['speed'] || (sheet&.derived_stats || {})[:speed]
      return 6 if speed_feet.to_i.zero?

      (speed_feet.to_i / SQUARE_FEET).clamp(1, 30)
    end

    # Updates the player token in the active battlefield row to (x, y) and
    # bumps the version. Returns the updated battlefield. Caller must already
    # hold a transaction if it needs strict atomicity with other mutations.
    def move_player_token!(adventure, x:, y:)
      battlefield = active_battlefield(adventure)
      raise ArgumentError, 'no active battlefield' unless battlefield

      tokens = battlefield.tokens.deep_dup
      player_token = tokens[PLAYER_TOKEN_ID]
      raise ArgumentError, 'player token missing from battlefield' unless player_token.is_a?(Hash)

      player_token['x'] = x.to_i
      player_token['y'] = y.to_i
      tokens[PLAYER_TOKEN_ID] = player_token

      battlefield.update!(tokens: tokens, version: battlefield.version.to_i + 1)
      sync_battlefield_ref!(adventure, battlefield)
      battlefield
    end

    def active_battlefield(adventure)
      adventure.adventure_battlefields.where(status: 'active').order(updated_at: :desc).first
    end

    def sync_battlefield_ref!(adventure, battlefield)
      ctx = adventure.combat_context.deep_dup.deep_stringify_keys
      ref = ctx['battlefield_ref']
      return unless ref.is_a?(Hash) && ref['id'].to_i == battlefield.id

      ctx['battlefield_ref'] = ref.merge('version' => battlefield.version)
      adventure.update!(combat_context: ctx)
    end
  end
end
