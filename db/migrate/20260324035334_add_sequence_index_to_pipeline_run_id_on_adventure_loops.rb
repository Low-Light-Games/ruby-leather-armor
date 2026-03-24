class AddSequenceIndexToPipelineRunIdOnAdventureLoops < ActiveRecord::Migration[7.1]
  def change
    add_index :adventure_loops, [:pipeline_run_id, :sequence_index],
              name: "index_adventure_loops_on_pipeline_run_id_and_sequence_index"
  end
end
