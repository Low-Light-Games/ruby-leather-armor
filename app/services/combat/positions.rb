# frozen_string_literal: true

module Combat
  module Positions
    SQUARE_FEET = 5
    PLAYER_TOKEN_ID = 'player'

    module_function

    def for_adventure(adventure)
      battlefield = active_battlefield(adventure)
      return [] unless battlefield

      Array(battlefield.tokens).filter_map do |token_id, raw|
        position_from_token(token_id, raw)
      end
    end

    def player_position(adventure)
      for_adventure(adventure).find { |p| p.token_id == PLAYER_TOKEN_ID }
    end

    def position_for_creature_sheet(adventure, creature_sheet_id)
      for_adventure(adventure).find { |p| p.creature_sheet_id.to_i == creature_sheet_id.to_i }
    end

    def occupied?(adventure, at_x:, at_y:, except_token_id: nil)
      for_adventure(adventure).any? do |position|
        next false unless position.coordinates_present?

        next false if position.token_id == except_token_id

        position.x.to_i == at_x.to_i && position.y.to_i == at_y.to_i
      end
    end

    def speed_squares_for(sheet)
      stats = sheet&.derived_stats || {}
      speed_feet = stats['speed'] || stats[:speed]
      return 6 if speed_feet.to_i.zero?

      (speed_feet.to_i / SQUARE_FEET).clamp(1, 30)
    end

    def move_player_token!(adventure, at_x:, at_y:)
      move_token!(adventure, token_id: PLAYER_TOKEN_ID, at_x: at_x, at_y: at_y)
    end

    def move_token!(adventure, token_id:, at_x:, at_y:)
      battlefield = active_battlefield(adventure)
      raise ArgumentError, 'no active battlefield' unless battlefield

      tokens = battlefield.tokens.deep_dup
      token = tokens[token_id.to_s]
      raise ArgumentError, "token missing from battlefield: #{token_id.inspect}" unless token.is_a?(Hash)

      token['x'] = at_x.to_i
      token['y'] = at_y.to_i
      tokens[token_id.to_s] = token

      battlefield.update!(tokens: tokens, version: battlefield.version.to_i + 1)
      sync_battlefield_ref!(adventure, battlefield)
      battlefield
    end

    def active_battlefield(adventure)
      adventure.adventure_battlefields.where(status: 'active').order(updated_at: :desc).first
    end

    def position_from_token(token_id, raw)
      return nil unless raw.is_a?(Hash)

      Combat::Position.new(
        token_id: token_id.to_s,
        label: raw['label'].to_s,
        coordinates: { x: raw['x'], y: raw['y'] },
        type: raw['type'],
        creature_sheet_id: raw['creature_sheet_id']
      )
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
