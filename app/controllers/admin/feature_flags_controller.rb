# frozen_string_literal: true

module Admin
  class FeatureFlagsController < ApplicationController
    before_action :require_admin

    def index
      @flags = FeatureFlag.order(:key)
      render layout: "application"
    end

    def toggle
      flag = FeatureFlag.find(params[:id])
      flag.update!(enabled: !flag.enabled?)
      redirect_to admin_feature_flags_path, notice: "#{flag.key} is now #{flag.enabled? ? 'enabled' : 'disabled'}."
    end

    private

    def require_admin
      redirect_to root_path, alert: "Unauthorized" unless current_user&.admin?
    end
  end
end
