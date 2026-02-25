# frozen_string_literal: true

class AddLevelAndSnapshotToSheets < ActiveRecord::Migration[7.1]
  def change
    add_column :sheets, :level, :integer, default: 1, null: false
    add_column :sheets, :snapshot, :boolean, default: false, null: false
    add_index :sheets, :snapshot
  end
end
