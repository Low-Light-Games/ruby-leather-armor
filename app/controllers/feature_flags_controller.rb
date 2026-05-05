# frozen_string_literal: true

class FeatureFlagsController < ApplicationController
  def index
    render json: { enabled: FeatureFlag.on_for_user(current_user).map(&:key) }
  end
end
