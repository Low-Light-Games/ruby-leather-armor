# frozen_string_literal: true

# Renamed from 20260525120000 to break a timestamp collision with
# 20260525120000_add_use_gamemaster_orchestrator_to_adventures.rb. Existing
# environments already applied this under the old version, so each operation
# is guarded for idempotency on re-run.
class AddUserIdToAdventureMessages < ActiveRecord::Migration[7.1]
  def change
    unless column_exists?(:adventure_messages, :user_id)
      add_reference :adventure_messages, :user, null: true, foreign_key: true, index: false
    end

    unless index_exists?(:adventure_messages, [:user_id, :created_at])
      add_index :adventure_messages, [:user_id, :created_at]
    end
  end
end
