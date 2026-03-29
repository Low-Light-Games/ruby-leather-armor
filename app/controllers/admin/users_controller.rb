# frozen_string_literal: true

module Admin
  class UsersController < BaseController
    before_action :set_user, only: [:show, :ban, :unban, :trust, :untrust]

    def index
      @users = User.order(created_at: :desc)
                   .select(:id, :email, :admin, :tier, :banned, :banned_at, :trusted,
                           :moderation_strikes, :created_at)
    end

    def show
      @moderation_events = @user.moderation_events.recent.limit(20)
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
  end
end
