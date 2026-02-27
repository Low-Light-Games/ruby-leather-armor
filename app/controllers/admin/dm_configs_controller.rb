module Admin
  class DmConfigsController < ApplicationController
    before_action :require_admin

    def show
      @config = DmConfig.instance
      render layout: 'application'
    end

    def update
      @config = DmConfig.instance

      new_settings = @config.settings.dup

      # Boolean toggles
      new_settings["verbose"] = params[:verbose] == "1"

      # Numeric settings
      if params[:temperature].present?
        temp = params[:temperature].to_f.clamp(0.0, 2.0)
        new_settings["temperature"] = temp
      end

      if params[:pacing_words_min].present?
        new_settings["pacing_words_min"] = params[:pacing_words_min].to_i.clamp(30, 500)
      end

      if params[:pacing_words_max].present?
        new_settings["pacing_words_max"] = params[:pacing_words_max].to_i.clamp(50, 1000)
      end

      if params[:sanitization_threshold].present?
        new_settings["sanitization_threshold"] = params[:sanitization_threshold].to_i.clamp(0, 100)
      end

      if params[:classification_mode].present? && %w[merged parallel].include?(params[:classification_mode])
        new_settings["classification_mode"] = params[:classification_mode]
      end

      if params[:response_mode].present? && %w[unified sequential].include?(params[:response_mode])
        new_settings["response_mode"] = params[:response_mode]
      end

      @config.update!(settings: new_settings)
      redirect_to admin_dm_config_path, notice: "DM settings updated."
    end

    private

    def require_admin
      unless current_user&.admin?
        redirect_to root_path, alert: "Unauthorized"
      end
    end
  end
end
