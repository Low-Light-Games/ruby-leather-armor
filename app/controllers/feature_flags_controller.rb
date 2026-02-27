# frozen_string_literal: true

class FeatureFlagsController < ApplicationController
  def index
    flags = FeatureFlag.where(enabled: true).pluck(:key)
    render json: { enabled: flags }
  end
end
