class NullifyAdventureLoopsAdventureId < ActiveRecord::Migration[7.1]
  def change
    remove_foreign_key :adventure_loops, :adventures
    change_column_null :adventure_loops, :adventure_id, true
    add_foreign_key :adventure_loops, :adventures, on_delete: :nullify
  end
end
