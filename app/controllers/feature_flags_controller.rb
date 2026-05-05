# frozen_string_literal: true

class FeatureFlagsController < ApplicationController
  def index
    keys = FeatureFlag.ordered.select { |flag| flag.enabled_for?(current_user) }.map(&:key)
    render json: { enabled: keys }
  end
end
