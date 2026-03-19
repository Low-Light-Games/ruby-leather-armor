# frozen_string_literal: true

module Admin
  class BaseController < ApplicationController
    before_action :require_admin
    before_action :set_active_nav

    layout 'admin'

    private

    CONTROLLER_NAV_MAP = {
      'adventures'       => :adventures,
      'stories'          => :stories,
      'play_logs'        => :play_logs,
      'dm_configs'       => :dm_config,
      'billing'          => :billing,
      'bestiary_entries' => :bestiary,
      'feature_flags'    => :feature_flags
    }.freeze

    def set_active_nav
      @active_nav = CONTROLLER_NAV_MAP[controller_name]
    end
  end
end
