# frozen_string_literal: true

class AddDmPipelinesAndDropRegistryStepCount < ActiveRecord::Migration[7.1]
  def change
    create_table :pipelines do |t|
      t.references :adventure, null: false, foreign_key: true
      t.references :player_message, null: true, foreign_key: { to_table: :adventure_messages }
      t.timestamps
    end

    add_reference :adventure_loops, :pipeline, foreign_key: true

    remove_column :pipeline_registry_entries, :step_count, :integer
  end
end
