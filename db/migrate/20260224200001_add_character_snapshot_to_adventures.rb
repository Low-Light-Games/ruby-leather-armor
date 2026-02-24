class AddCharacterSnapshotToAdventures < ActiveRecord::Migration[7.1]
  def change
    add_column :adventures, :character_snapshot, :json, null: false, default: {}
  end
end
