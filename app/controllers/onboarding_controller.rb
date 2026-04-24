# frozen_string_literal: true

class OnboardingController < ApplicationController
  def complete
    character_type = params[:character_type].to_s.downcase
    unless %w[rogue fighter].include?(character_type)
      return render json: { error: "Invalid character type" }, status: :unprocessable_entity
    end

    story = Story.kept.order("RANDOM()").first
    unless story
      return render json: { error: "No adventures are available yet. Build your own character to get started." }, status: :unprocessable_entity
    end

    ActiveRecord::Base.transaction do
      sheet = Sheets::StarterProvisioner.ensure_for(user: current_user, starter_key: character_type)
      adventure = build_adventure!(story, sheet)
      current_user.update!(onboarding_state: "in_progress")
      render json: { adventure_id: adventure.id }, status: :created
    end
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def build_adventure!(story, sheet)
    Adventures::Bootstrap.new(
      story:                   story,
      sheet:                   sheet,
      user:                    current_user,
      directed_dm:             true,
      skip_world_sanity_check: false
    ).call
  end

end
