class AddAppVersionToPlayLogsAndPipelineRuns < ActiveRecord::Migration[7.1]
  def change
    add_column :play_logs, :app_version, :string
    add_column :pipeline_runs, :app_version, :string
  end
end
