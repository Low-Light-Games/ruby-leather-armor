class AddExplorationRestInventoryContextsToAdventures < ActiveRecord::Migration[7.1]
  def change
    add_column :adventures, :exploration_context, :jsonb, default: {}, null: false
    add_column :adventures, :rest_context, :jsonb, default: {}, null: false
    add_column :adventures, :inventory_context, :jsonb, default: {}, null: false
  end
end
