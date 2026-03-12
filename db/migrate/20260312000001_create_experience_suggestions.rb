class CreateExperienceSuggestions < ActiveRecord::Migration[7.1]
  def change
    create_table :experience_suggestions do |t|
      t.references :adventure, null: false, foreign_key: true
      t.uuid :pipeline_run_id
      t.string :category, null: false
      t.string :source_step, null: false
      t.jsonb :details, default: {}, null: false
      t.boolean :reviewed, default: false, null: false
      t.timestamps
    end

    add_index :experience_suggestions, :category
    add_index :experience_suggestions, :reviewed
  end
end
