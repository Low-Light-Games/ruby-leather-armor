# frozen_string_literal: true

module Admin
  class EncountersController < ApplicationController
    before_action :require_admin

    PER_PAGE = 30

    def index
      @encounters = Encounter.includes(:adventure, encounter_participants: [:adventure_sheet, :creature_sheet])
                              .order(created_at: :desc)

      @encounters = @encounters.where(adventure_id: params[:adventure_id]) if params[:adventure_id].present?
      @encounters = @encounters.where(status: params[:status]) if params[:status].present?

      @page = [params[:page].to_i, 1].max
      @total_count = @encounters.count
      @total_pages = (@total_count.to_f / PER_PAGE).ceil
      @encounters = @encounters.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)

      render layout: "application"
    end

    def show
      @encounter = Encounter.includes(encounter_participants: [:adventure_sheet, :creature_sheet])
                            .find(params[:id])
      @participants = @encounter.encounter_participants.order(initiative: :desc, id: :asc)

      log_window_end = @encounter.completed? ? @encounter.updated_at : Time.current
      @combat_messages = @encounter.adventure.adventure_messages
                                   .where(created_at: @encounter.created_at..log_window_end)
                                   .order(created_at: :asc)
      @dm_logs = DmLog.where(adventure_id: @encounter.adventure_id)
                      .where(created_at: @encounter.created_at..log_window_end)
                      .order(created_at: :asc)

      render layout: "application"
    end

    private

    def require_admin
      redirect_to root_path, alert: "Unauthorized" unless current_user&.admin?
    end
  end
end
