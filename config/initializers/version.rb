APP_VERSION = File.read(Rails.root.join("VERSION")).strip

Rails.application.config.after_initialize do
  Rails.logger.info "leatherarmor.io v#{APP_VERSION} starting (#{Rails.env})"
end
