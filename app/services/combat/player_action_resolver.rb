# frozen_string_literal: true

module Combat
  class PlayerActionResolver
    Error = Combat::ResolverError

    SUPPORTED_KINDS = %w[attack move end_turn buff heal].freeze
    DEFENSE_KIND_TO_STAT = {
      'full_ac' => 'ac',
      'touch_ac' => 'touch_ac',
      'flat_footed_ac' => 'flat_footed_ac'
    }.freeze
    PLAYER_NAME = Combat::TurnCalculator::PLAYER_NAME

    include Combat::Resolvers::Attack
    include Combat::Resolvers::Move
    include Combat::Resolvers::EndPlayerTurn
    include Combat::Resolvers::Buff
    include Combat::Resolvers::Heal

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

      result = case @params[:kind].to_s
               when 'attack'   then resolve_attack
               when 'move'     then resolve_move
               when 'end_turn' then resolve_end_turn
               when 'buff'     then resolve_buff
               when 'heal'     then resolve_heal
               end

      Combat::ContextSync.refresh_participants!(@adventure, @sheet)
      maybe_end_combat!(result)
    end

    private

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

    def decrement_action_economy_with_delta!(delta, label:)
      @adventure.with_lock do
        ctx = @adventure.combat_context.deep_dup.deep_stringify_keys
        ctx['action_economy'] = Battlefield::ActionEconomy.apply_delta!(ctx['action_economy'], delta)
        @adventure.update!(combat_context: ctx)
      end
    rescue ArgumentError => e
      raise Combat::ResolverError.new("action economy refused #{label}: #{e.message}", code: :action_economy_refused)
    end

    def maybe_end_combat!(result)
      return result unless result.is_a?(Hash)

      end_state = Combat::EndResolver.check_combat_end(
        adventure: @adventure, sheet: @sheet,
        instant_death: defined?(DmConfig) ? DmConfig.instance.instant_death? : false
      )
      return result if end_state[:combat][:combat_active]

      apply_combat_ended!(end_state)
      annotate_result_with_combat_end(result, end_state)
    end

    def apply_combat_ended!(end_state)
      reason = end_state[:combat][:combat_end_reason].to_s
      @adventure.with_lock do
        ctx = @adventure.combat_context.deep_dup.deep_stringify_keys
        ctx['active'] = false
        ctx['current_turn'] = nil
        ctx['action_economy'] = nil
        ctx['combat_end_reason'] = reason
        @adventure.update!(combat_context: ctx)
      end
      apply_player_death_terminus! if reason == 'player_death'
      broadcast_combat_end_narration!(reason)
    rescue StandardError => e
      Rails.logger.warn("[PlayerActionResolver] combat-end persist failed: #{e.message}")
    end

    def broadcast_combat_end_narration!(reason)
      return if reason == 'player_death'

      content = combat_end_narration_for(reason)
      return if content.blank?

      msg = @adventure.adventure_messages.create!(
        role: 'system', content: content, message_type: 'combat_end'
      )
      AdventureChannel.broadcast_to(
        @adventure,
        type: 'pipeline_action_result',
        messages: [DungeonMaster::AdventurePlay::MessageSerializer.as_json(msg, admin: @user&.admin?)]
      )
    end

    def combat_end_narration_for(reason)
      case reason
      when 'all_npcs_defeated' then 'Combat ends — every hostile is down. The battlefield falls quiet.'
      else 'Combat ends.'
      end
    end

    def apply_player_death_terminus!
      return if @adventure.ended?

      @adventure.mark_ended!(reason: 'player_death')
      msg = @adventure.adventure_messages.create!(
        role: 'system',
        content: 'Your character has died.',
        message_type: 'player_death'
      )
      AdventureChannel.broadcast_to(
        @adventure,
        type: 'pipeline_action_result',
        messages: [DungeonMaster::AdventurePlay::MessageSerializer.as_json(msg, admin: @user&.admin?)]
      )
    end

    def annotate_result_with_combat_end(result, end_state)
      payload = (result[:result] || {}).merge(
        combat_ended: true,
        combat_end_reason: end_state[:combat][:combat_end_reason].to_s
      )
      result.merge(result: payload)
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
      Combat::SocialEventTrigger.maybe_log!(@adventure, payload)
    rescue StandardError => e
      Rails.logger.warn("[PlayerActionResolver] play_log persist failed: #{e.message}")
    end
  end
end
