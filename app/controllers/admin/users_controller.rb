# frozen_string_literal: true

module Admin
  class UsersController < BaseController
    before_action :set_user, only: [:show, :ban, :unban, :trust, :untrust]

    def index
      @users = User.order(created_at: :desc)
      @users = @users.where("email ILIKE ?", "%#{params[:q]}%") if params[:q].present?
    end

    def show
      @moderation_events = @user.moderation_events.order(created_at: :desc)
    end

    def ban
      @user.update!(banned: true, banned_at: Time.current)
      redirect_to admin_user_path(@user), notice: "#{@user.email} has been banned."
    end

    def unban
      @user.update!(banned: false, banned_at: nil)
      redirect_to admin_user_path(@user), notice: "#{@user.email} has been unbanned."
    end

    def trust
      @user.update!(trusted: true)
      redirect_to admin_user_path(@user), notice: "#{@user.email} is now trusted."
    end

    def untrust
      @user.update!(trusted: false)
      redirect_to admin_user_path(@user), notice: "Trust revoked for #{@user.email}."
    end

    private

    def set_user
      @user = User.find(params[:id])
    end
  end
end
