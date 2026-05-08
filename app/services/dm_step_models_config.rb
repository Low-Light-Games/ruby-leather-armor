# frozen_string_literal: true

# Loads + caches config/dm_step_models.yml, the versioned source of truth
# for which model and reasoning_effort each pipeline step uses.
#
# DmConfig#model_for / #reasoning_effort_for / #model delegate here, so
# call sites in the pipeline (steps/*.rb) keep reading config.model_for(...)
# and don't have to know this is YAML-backed.
class DmStepModelsConfig
  REASONING_EFFORTS = %w[minimal low medium high].freeze
  CONFIG_PATH = Rails.root.join("config", "dm_step_models.yml")

  class << self
    def model_for(step)
      load_config.fetch("step_models", {})[step.to_s].presence ||
        default_model
    end

    def reasoning_effort_for(step)
      override = load_config.fetch("step_reasoning_efforts", {})[step.to_s].to_s
      return override if REASONING_EFFORTS.include?(override)

      default_reasoning_effort
    end

    def default_model
      load_config.fetch("default_model")
    end

    def default_reasoning_effort
      effort = load_config["default_reasoning_effort"].to_s
      REASONING_EFFORTS.include?(effort) ? effort : "minimal"
    end

    # Test-only: drop the cached parse so a spec can stub CONFIG_PATH or
    # force a re-read after editing the YAML at runtime.
    def reset_cache!
      @config = nil
    end

    private

    def load_config
      @config ||= begin
        raw = YAML.safe_load_file(CONFIG_PATH, permitted_classes: [Symbol]) || {}
        raw["step_models"] ||= {}
        raw["step_reasoning_efforts"] ||= {}
        raw.freeze
      end
    end
  end
end
