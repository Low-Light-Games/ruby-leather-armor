# frozen_string_literal: true

class AddDmServiceToAiLogs < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_logs, :dm_service, :string, default: "standard", null: false
    add_index :ai_logs, :dm_service
  end
end
