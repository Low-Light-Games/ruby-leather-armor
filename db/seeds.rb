# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

require 'bcrypt'

# Development-only users — reference data and story content are handled
# by data migrations and will already be present after db:migrate.

admin = User.find_or_initialize_by(email: 'admin@example.com')
admin.admin = true
admin.password_digest = BCrypt::Password.create('admin123')
admin.save!

test_user = User.find_or_initialize_by(email: 'test@example.com')
test_user.admin = false
test_user.password_digest = BCrypt::Password.create('test123')
test_user.save!

puts "Created/updated admin user: #{admin.email} (password: admin123)"
puts "Created/updated test user: #{test_user.email} (password: test123)"
