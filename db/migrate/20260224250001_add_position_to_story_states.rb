class AddPositionToStoryStates < ActiveRecord::Migration[7.1]
  def change
    add_column :story_states, :position, :integer, null: false, default: 0

    # Backfill positions based on existing ID order within each story
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE story_states
          SET position = sub.row_num - 1
          FROM (
            SELECT id, ROW_NUMBER() OVER (PARTITION BY story_id ORDER BY id) AS row_num
            FROM story_states
          ) sub
          WHERE story_states.id = sub.id
        SQL
      end
    end
  end
end
