# Share the session cookie across all subdomains when APP_URL is configured
# (i.e. in production). This lets an admin who logged in on app.leatherarmor.io
# carry that session to leatherarmor.io/admin/... without having to log in again.
#
# Derived from APP_URL so no additional env var is needed:
#   https://app.leatherarmor.io  →  .leatherarmor.io
#
# Locally (APP_URL blank) no domain attribute is set, which is the Rails default.
session_domain = if (app_url = ENV["APP_URL"]).present?
  host = URI.parse(app_url).host                  # "app.leatherarmor.io"
  ".#{host.split('.').last(2).join('.')}"          # ".leatherarmor.io"
end

Rails.application.config.session_store :cookie_store,
  key:    '_app_session',
  domain: session_domain
