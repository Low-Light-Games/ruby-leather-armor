# frozen_string_literal: true

class AddUseGamemasterOrchestratorToAdventures < ActiveRecord::Migration[7.1]
  def change
    add_column :adventures, :use_gamemaster_orchestrator, :boolean, default: false, null: false
  end
end
