# frozen_string_literal: true

# Seed scripts intentionally use short, memorable passwords like "test123" so
# local dev / Playwright runs are easy to log in with. Bypass the password
# length validation for the duration of `db:seed` so the model can keep
# enforcing minimum: 8 everywhere else.
namespace :db do
  task seed_bypass_password_length: :environment do
    Thread.current[:skip_user_password_length_validation] = true
  end
end

Rake::Task["db:seed"].enhance(["db:seed_bypass_password_length"]) do
  Thread.current[:skip_user_password_length_validation] = false
end
