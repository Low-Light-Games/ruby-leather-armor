# frozen_string_literal: true

class AddReasoningEffortToPlayLogs < ActiveRecord::Migration[7.1]
  def change
    add_column :play_logs, :reasoning_effort, :string
  end
end
