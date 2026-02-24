class AddUserIdToSheets < ActiveRecord::Migration[7.1]
  def up
    # Add column as nullable first
    add_reference :sheets, :user, null: true, foreign_key: true
    
    # Create a default admin user if it doesn't exist
    admin = User.find_or_create_by!(email: 'migration_admin@example.com') do |u|
      u.password = SecureRandom.hex(16)
      u.password_confirmation = u.password
      u.admin = true
    end
    
    # Assign all existing sheets to the admin user
    Sheet.where(user_id: nil).update_all(user_id: admin.id)
    
    # Now make it non-nullable
    change_column_null :sheets, :user_id, false
  end

  def down
    remove_reference :sheets, :user, foreign_key: true
  end
end
