# frozen_string_literal: true

module Combat
  # Deterministic resolver for a single player combat action initiated
  # from the combat HUD (PR-B of the combat-determinism arc — see
  # docs/combat_redesign.md). The AI is NOT in this path; for the
  # routine cases — pick an attack option, pick a target, resolve hit
  # + damage + HP delta — this is the entire pipeline.
  #
  # Two dice strategies, selected by `User#combat_dice_strategy`:
  #
  #   * "server" — RNG happens here, the resolver returns the final
  #     `:resolved` result in one round-trip.
  #   * "client" — the resolver returns a `:awaiting_player_dice`
  #     payload describing the rolls the player needs to make. The
  #     frontend posts the natural results back; a second `.call` with
  #     `submitted_dice:` resolves the action.
  #
  # The same shape comes back to the controller in both branches so the
  # frontend has one rendering surface.
  #
  # The dispatcher itself is intentionally small: action-kind validation,
  # action-economy bookkeeping, action_event logging. The heavy lifting
  # lives in the per-kind Resolvers::* concerns.
  class PlayerActionResolver
    # Backwards-compatible alias for the pre-refactor error class. New
    # code raises Combat::ResolverError directly; existing callers that
    # rescue PlayerActionResolver::Error keep working.
    Error = Combat::ResolverError

    SUPPORTED_KINDS = %w[attack move end_turn].freeze
    DEFENSE_KIND_TO_STAT = {
      'full_ac' => 'ac',
      'touch_ac' => 'touch_ac',
      'flat_footed_ac' => 'flat_footed_ac'
    }.freeze
    PLAYER_NAME = DungeonMaster::Utilities::CombatTurnCalculator::PLAYER_NAME

    include Combat::Resolvers::Attack
    include Combat::Resolvers::Move
    include Combat::Resolvers::EndTurn

    def self.call(**)
      new(**).call
    end

    def initialize(adventure:, sheet:, user:, params:, submitted_dice: nil)
      @adventure = adventure
      @sheet = sheet
      @user = user
      @params = (params || {}).deep_symbolize_keys
      @submitted_dice = submitted_dice&.deep_symbolize_keys
    end

    def call
      ensure_combat_active!
      ensure_player_turn!
      ensure_supported_kind!

      case @params[:kind].to_s
      when 'attack'   then resolve_attack
      when 'move'     then resolve_move
      when 'end_turn' then resolve_end_turn
      end
    end

    private

    # ── Validation ──────────────────────────────────────────────────────

    def ensure_combat_active!
      return if @adventure.combat_active?

      raise Combat::ResolverError.new('combat is not active', code: :combat_not_active)
    end

    def ensure_player_turn!
      ctx = @adventure.combat_context || {}
      turn = ctx['current_turn'].to_s
      return if turn == PLAYER_NAME

      raise Combat::ResolverError.new("not the player's turn (current: #{turn.presence || 'unknown'})",
                                      code: :not_player_turn)
    end

    def ensure_supported_kind!
      kind = @params[:kind].to_s
      return if SUPPORTED_KINDS.include?(kind)

      raise Combat::ResolverError.new("unsupported combat action kind: #{kind.inspect}", code: :unsupported_kind)
    end

    # ── Shared helpers used across resolver concerns ────────────────────

    def decrement_action_economy_with_delta!(delta, label:)
      ctx = @adventure.combat_context.deep_dup.deep_stringify_keys
      ctx['action_economy'] = DungeonMaster::Battlefield::ActionEconomy.apply_delta!(ctx['action_economy'], delta)
      @adventure.update!(combat_context: ctx)
    rescue ArgumentError => e
      raise Combat::ResolverError.new("action economy refused #{label}: #{e.message}", code: :action_economy_refused)
    end

    def log_action_event!(payload)
      PlayLog.create!(
        adventure: @adventure,
        event_type: 'combat_action',
        prompt_summary: payload[:message].to_s.truncate(200),
        parsed_response: payload.to_json,
        status: 'pipeline_event',
        app_version: defined?(APP_VERSION) ? APP_VERSION : nil
      )
    rescue StandardError => e
      Rails.logger.warn("[PlayerActionResolver] play_log persist failed: #{e.message}")
    end
  end
end
