class AddUserIdToAdventures < ActiveRecord::Migration[7.1]
  def up
    add_reference :adventures, :user, null: true, foreign_key: true

    # Backfill user_id from the associated sheet
    execute <<-SQL
      UPDATE adventures
      SET user_id = sheets.user_id
      FROM sheets
      WHERE adventures.sheet_id = sheets.id
    SQL

    change_column_null :adventures, :user_id, false
  end

  def down
    remove_reference :adventures, :user
  end
end
