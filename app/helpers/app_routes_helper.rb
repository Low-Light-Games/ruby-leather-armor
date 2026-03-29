# frozen_string_literal: true

# Single source for window.AppRoutes (layouts/_app_routes.html.erb) and any
# server-rendered links that must match the same rules (e.g. admin navbar).
module AppRoutesHelper
  def app_routes_for_request
    @app_routes_for_request ||= build_app_routes_for_request
  end

  def app_routes_app_base
    app_routes_for_request[:app_base]
  end

  def app_routes_main_url
    app_routes_for_request[:main_url]
  end

  def player_new_adventure_href
    app_routes_for_request[:new_adventure]
  end

  private

  def build_app_routes_for_request
    app_url_raw  = ENV["APP_URL"].presence
    app_url_host = app_url_raw ? URI.parse(app_url_raw).host : nil
    app_base     = (app_url_host && request.host == app_url_host) ? "" : "/app"
    main_url     = app_url_host ? app_url_raw.sub("//#{app_url_host}", "//#{app_url_host.sub(/\Aapp\./, '')}") : ""
    main_host    = app_url_host&.sub(/\Aapp\./, "")

    on_main_domain = app_url_raw.present? && main_host.present? && (
      request.host == main_host || request.host == "www.#{main_host}"
    )

    new_adventure =
      if app_url_raw.present? && app_url_host && request.host == app_url_host
        "#{app_base}/adventures/new"
      elsif on_main_domain
        "#{app_url_raw.chomp('/')}/adventures/new"
      else
        "#{app_base}/adventures/new"
      end

    { app_base: app_base, main_url: main_url, new_adventure: new_adventure }
  end
end
