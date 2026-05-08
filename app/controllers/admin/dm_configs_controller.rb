module Admin
  class DmConfigsController < BaseController

    def show
      @config = DmConfig.instance
      render layout: 'admin'
    end

    def update
      @config = DmConfig.instance

      new_settings = @config.settings.dup

      # Boolean toggles
      new_settings["instant_death"]           = params[:instant_death]    == "1"
      new_settings["no_auto_hit_miss"]         = params[:no_auto_hit_miss] == "1"

      # Action queue — 3-state: false / "progressive" / "progressive_continuity"
      new_settings["action_queue"] =
        %w[progressive progressive_continuity].include?(params[:action_queue]) \
          ? params[:action_queue] \
          : false

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

      # Per-step model + reasoning_effort assignments live in
      # config/dm_step_models.yml — versioned, not editable here.

      if params[:narrative_facts_embedding_model].present? &&
         DmConfig::EMBEDDING_MODEL_IDS.include?(params[:narrative_facts_embedding_model])
        new_settings["narrative_facts_embedding_model"] = params[:narrative_facts_embedding_model]
      end

      if params[:narrative_facts_top_k].present?
        new_settings["narrative_facts_top_k"] = params[:narrative_facts_top_k].to_i.clamp(1, 50)
      end

      if params[:narrative_facts_active_window].present?
        new_settings["narrative_facts_active_window"] = params[:narrative_facts_active_window].to_i.clamp(0, 200)
      end

      if params[:stripe_grace_period_days].present?
        new_settings["stripe_grace_period_days"] = params[:stripe_grace_period_days].to_i.clamp(1, 30)
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
