module Admin
  class DmConfigsController < BaseController

    def show
      @config = DmConfig.instance
      available_ids = fetch_available_model_ids
      @models_with_metadata = OpenaiModelCatalog.for_models(available_ids)
      render layout: 'admin'
    end

    def update
      @config = DmConfig.instance

      new_settings = @config.settings.dup

      # Boolean toggles
      new_settings["chronicler_tone_direction"] = params[:chronicler_tone_direction] == "1"
      new_settings["action_queue"] = params[:action_queue] == "1"
      new_settings["per_action_narration"] = params[:per_action_narration] == "1"

      # Evaluation mode toggle
      if %w[unified parallel].include?(params[:evaluation_mode])
        new_settings["evaluation_mode"] = params[:evaluation_mode]
      end

      # Numeric settings
      if params[:temperature].present?
        temp = params[:temperature].to_f.clamp(0.0, 2.0)
        new_settings["temperature"] = temp
      end

      if params[:pacing_words_min].present?
        new_settings["pacing_words_min"] = params[:pacing_words_min].to_i.clamp(10, 500)
      end

      if params[:pacing_words_max].present?
        new_settings["pacing_words_max"] = params[:pacing_words_max].to_i.clamp(20, 1000)
      end

      if params[:danger_threshold].present?
        new_settings["danger_threshold"] = params[:danger_threshold].to_i.clamp(0, 100)
      end

      if params[:model].present?
        new_settings["model"] = params[:model]
      end

      new_settings["enricher_model"] = params[:enricher_model].presence
      new_settings["embellisher_model"] = params[:embellisher_model].presence

      if params[:embellisher_mode].present? && DmConfig::EMBELLISHER_MODES.include?(params[:embellisher_mode])
        new_settings["embellisher_mode"] = params[:embellisher_mode]
      end

      if params[:step_models].present?
        models = {}
        DmConfig::TOKEN_BUDGET_STEPS.each do |step|
          val = params[:step_models][step]
          models[step] = val if val.present?
        end
        new_settings["step_models"] = models
      end

      if params[:token_budgets].present?
        budgets = {}
        DmConfig::TOKEN_BUDGET_STEPS.each do |step|
          val = params[:token_budgets][step]
          budgets[step] = val.to_i.clamp(100, 16_000) if val.present?
        end
        new_settings["token_budgets"] = budgets if budgets.any?
      end

      @config.update!(settings: new_settings)
      redirect_to admin_dm_config_path, notice: "DM settings updated."
    end

    def models
      render json: OpenaiModelCatalog.for_models(fetch_available_model_ids)
    end

    private

    def fetch_available_model_ids
      client = OpenAI::Client.new
      response = client.models.list
      response.fetch("data", [])
        .map { |m| m["id"] }
        .select { |id| OpenaiModelCatalog.chat_model?(id) }
        .sort
    rescue StandardError => e
      Rails.logger.error("[DmConfigsController] Failed to fetch OpenAI models: #{e.message}")
      [DmConfig::DEFAULTS["model"]]
    end

    def require_admin
      unless current_user&.admin?
        redirect_to root_path, alert: "Unauthorized"
      end
    end
  end
end
