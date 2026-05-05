# frozen_string_literal: true

module Admin
  class FeatureFlagsController < BaseController
    def index
      @flags = FeatureFlag.ordered
      render layout: "admin"
    end

    def edit
      @flag = FeatureFlag.find(params[:id])
      render layout: "admin"
    end

    def update
      @flag = FeatureFlag.find(params[:id])
      if @flag.update(flag_params)
        redirect_to admin_feature_flags_path, notice: "#{@flag.key} updated."
      else
        flash.now[:alert] = @flag.errors.full_messages.to_sentence
        render :edit, layout: "admin", status: :unprocessable_entity
      end
    end

    private

    def flag_params
      permitted = params.require(:feature_flag).permit(
        :mode,
        :bucketing_strategy,
        :modulo_divisor,
        :granular_user_ids_raw,
        modulo_on_remainders: []
      )

      attrs = {
        mode: permitted[:mode],
        bucketing_strategy: permitted[:bucketing_strategy].presence,
        granular_user_ids: parse_granular_ids(permitted[:granular_user_ids_raw]),
        modulo_divisor: permitted[:modulo_divisor].presence&.to_i,
        modulo_on_remainders: Array(permitted[:modulo_on_remainders]).map(&:to_i)
      }

      # Clear bucketing-only fields when mode != bucketed so flipping back to
      # "on" doesn't leave stale bucket config behind.
      if attrs[:mode] != "bucketed"
        attrs[:bucketing_strategy] = nil
        attrs[:granular_user_ids] = []
        attrs[:modulo_divisor] = nil
        attrs[:modulo_on_remainders] = []
      end

      attrs
    end

    def parse_granular_ids(raw)
      return [] if raw.blank?

      raw.scan(/\d+/).map(&:to_i).uniq
    end

    def require_admin
      redirect_to root_path, alert: "Unauthorized" unless current_user&.admin?
    end
  end
end
