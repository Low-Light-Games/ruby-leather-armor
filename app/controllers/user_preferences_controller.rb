# frozen_string_literal: true

# Per-user preferences that are flippable mid-session from the UI without
# bouncing through the full settings/onboarding flows.
class UserPreferencesController < ApplicationController
  # PATCH /user_preferences
  #
  # Body: { combat_dice_strategy: "client" | "server" }
  def update
    strategy = params[:combat_dice_strategy].to_s
    return render_invalid_strategy(strategy) unless picked_strategy_valid?(strategy)

    current_user.update!(combat_dice_strategy: strategy)
    render json: { combat_dice_strategy: current_user.combat_dice_strategy }
  end

  private

  def picked_strategy_valid?(strategy)
    User::COMBAT_DICE_STRATEGIES.include?(strategy)
  end

  def render_invalid_strategy(strategy)
    render json: { error: "invalid combat_dice_strategy: #{strategy.inspect}" }, status: :unprocessable_entity
  end
end
