# frozen_string_literal: true

# Per-user preferences that are flippable mid-session from the UI without
# bouncing through the full settings/onboarding flows.
class UserPreferencesController < ApplicationController
  # PATCH /user_preferences
  #
  # Body: { combat_dice_strategy: "client" | "server" }
  def update
    strategy = params[:combat_dice_strategy].to_s
    unless User::COMBAT_DICE_STRATEGIES.include?(strategy)
      return render json: { error: "invalid combat_dice_strategy: #{strategy.inspect}" },
                    status: :unprocessable_entity
    end

    current_user.update!(combat_dice_strategy: strategy)
    render json: { combat_dice_strategy: current_user.combat_dice_strategy }
  end
end
