class AdminController < ApplicationController
  def all_sheets
    authorize(:admin, :all_sheets?)
    @sheets = policy_scope(Sheet).order(created_at: :desc)
    render json: @sheets
  end
end
