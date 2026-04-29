# frozen_string_literal: true

# Combat HUD endpoints — deterministic per-action resolution that bypasses
# the AI pipeline (PR-B of the combat-determinism arc; see
# docs/combat_redesign.md).
class CombatActionsController < ApplicationController
  before_action :set_adventure
  before_action -> { authorize(@adventure, :show?) }
  before_action -> { authorize(@adventure, :pipeline?) }, only: %i[create]
  before_action :check_ban
  before_action :reject_ended_adventure!, only: %i[create]
  before_action :set_adventure_sheet

  # GET /adventures/:adventure_id/combat_action/options
  #
  # Returns the attack options the HUD can render right now (subject to
  # action-economy availability) and the live participant list so the
  # frontend can pick a target. Cheap, no AI, no mutations.
  def options
    battlefield = DungeonMaster::Battlefield::ApiSnapshot.for_adventure(@adventure)
    player_pos = Combat::Positions.player_position(@adventure)
    render json: {
      attack_options: attack_options_for_render,
      targets: hostile_targets,
      action_economy: combat_context_hash['action_economy'],
      dice_strategy: current_user.combat_dice_strategy,
      battlefield: battlefield,
      player_position: player_pos&.coordinates_present? ? { x: player_pos.x, y: player_pos.y } : nil,
      player_speed_squares: Combat::Positions.speed_squares_for(@adventure_sheet)
    }
  end

  # POST /adventures/:adventure_id/combat_action
  #
  # Body: { kind: "attack", attack_option_id, target_creature_sheet_id, submitted_dice? }
  def create
    result = Combat::PlayerActionResolver.call(
      adventure: @adventure,
      sheet: @adventure_sheet,
      user: current_user,
      params: combat_action_params,
      submitted_dice: submitted_dice_params
    )
    render json: result.merge(combat_context: @adventure.reload.combat_context)
  rescue Combat::PlayerActionResolver::Error => e
    render json: { error: e.message, code: e.code }, status: :unprocessable_entity
  end

  private

  def set_adventure
    @adventure = Adventure.kept.find(params[:adventure_id])
  end

  def set_adventure_sheet
    @adventure_sheet = @adventure.adventure_sheets.first!
  end

  def check_ban
    return unless current_user&.banned?

    render json: {
      banned: true,
      message: 'Your account has been suspended. Contact appeals@leatheramor.io for assistance.'
    }, status: :forbidden
  end

  def reject_ended_adventure!
    return unless @adventure.ended?

    render json: { error: 'adventure has ended' }, status: :unprocessable_entity
  end

  def combat_action_params
    params.permit(:kind, :attack_option_id, :target_creature_sheet_id, :x, :y, :withdraw).to_h
  end

  def submitted_dice_params
    return nil unless params[:submitted_dice].is_a?(ActionController::Parameters) || params[:submitted_dice].is_a?(Hash)

    params.require(:submitted_dice).permit(:attack_natural, :damage_natural).to_h
  end

  def attack_options_for_render
    DungeonMaster::Combat::AttackOptionBuilder.call(sheet: @adventure_sheet, adventure: @adventure)
  end

  def hostile_targets
    @hostile_targets ||= combat_participants.filter_map do |participant|
      next if participant_is_player?(participant)

      sid = participant['creature_sheet_id']
      next if sid.blank?

      creature = @adventure.creature_sheets.find_by(id: sid.to_i)
      next unless creature

      Combat::HostileTarget.new(creature).to_h
    end
  end

  def combat_participants
    @combat_participants ||= Array(combat_context_hash['participants'])
  end

  def combat_context_hash
    @adventure.combat_context.is_a?(Hash) ? @adventure.combat_context : {}
  end

  def participant_is_player?(participant)
    participant['name'].to_s.casecmp(DungeonMaster::Utilities::CombatTurnCalculator::PLAYER_NAME).zero?
  end
end
