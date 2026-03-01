# frozen_string_literal: true

class DropDormantTablesAndAddMicroContexts < ActiveRecord::Migration[7.1]
  def change
    # Drop dormant tables (order respects foreign keys)
    drop_table :encounter_participants, if_exists: true
    drop_table :encounters, if_exists: true
    drop_table :location_edges, if_exists: true
    drop_table :locations, if_exists: true

    # Replace single free-text immediate_context with typed JSONB micro contexts
    change_table :adventures do |t|
      t.remove :immediate_context, type: :text
      t.jsonb :traversal_context, default: {}, null: false
      t.jsonb :combat_context, default: {}, null: false
      t.jsonb :social_context, default: {}, null: false
    end
  end
end
