# frozen_string_literal: true

module Admin
  class UsersController < BaseController
    before_action :set_user, only: [:show, :update_plan, :ban, :unban, :trust, :untrust]

    def index
      @users = User.for_admin_index
      # Single grouped query keyed by user_id to avoid N+1 on the user list.
      @player_message_stats = AdventureMessage
                              .from_players
                              .joins(:adventure)
                              .group("adventures.user_id")
                              .pluck("adventures.user_id", Arel.sql("MAX(adventure_messages.created_at)"), Arel.sql("COUNT(*)"))
                              .each_with_object({}) do |(user_id, last_at, count), memo|
        memo[user_id] = { last_at: last_at, count: count }
      end
    end

    def show
      @moderation_events = @user.moderation_events.recent.limit(20)
      @recent_messages = AdventureMessage.where(adventure_id: @user.adventure_ids)
                                         .from_players
                                         .newest_first
                                         .includes(:adventure)
                                         .limit(30)
    end

    def update_plan
      target_plan_key = plan_params[:plan_key]
      unless valid_plan_key?(target_plan_key)
        render_invalid_plan_selection!
        return
      end

      profile = @user.stripe_profile || @user.create_stripe_profile!
      profile.update!(plan_key: target_plan_key)
      redirect_to admin_users_path, notice: "#{@user.email} plan updated to #{target_plan_key}."
    end

    def ban
      @user.update!(banned: true, banned_at: Time.current)
      redirect_to admin_users_path, notice: "#{@user.email} has been banned."
    end

    def unban
      @user.update!(banned: false, banned_at: nil)
      redirect_to admin_users_path, notice: "#{@user.email} has been unbanned."
    end

    def trust
      @user.update!(trusted: true)
      redirect_to admin_users_path, notice: "#{@user.email} is now a trusted user."
    end

    def untrust
      @user.update!(trusted: false)
      redirect_to admin_users_path, notice: "#{@user.email} trust has been revoked."
    end

    private

    def require_admin
      redirect_to root_path, alert: "Unauthorized" unless current_user&.admin?
    end

    def set_user
      @user = User.find(params[:id])
    end

    def plan_params
      params.require(:user).permit(:plan_key)
    end

    def valid_plan_key?(target_plan_key)
      StripePlans::PLAN_KEYS.include?(target_plan_key)
    end

    def render_invalid_plan_selection!
      redirect_to admin_users_path, alert: "Invalid plan selected."
    end
  end
end
