# frozen_string_literal: true

class EnsureUseGamemasterOrchestratorOnAdventures < ActiveRecord::Migration[7.1]
  def change
    return if column_exists?(:adventures, :use_gamemaster_orchestrator)

    add_column :adventures, :use_gamemaster_orchestrator, :boolean, default: false, null: false
  end
end
