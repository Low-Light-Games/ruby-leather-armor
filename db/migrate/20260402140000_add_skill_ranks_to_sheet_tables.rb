# frozen_string_literal: true

class AddSkillRanksToSheetTables < ActiveRecord::Migration[7.1]
  def change
    add_column :sheets, :skill_ranks, :jsonb, default: {}, null: false
    add_column :adventure_sheets, :skill_ranks, :jsonb, default: {}, null: false
  end
end
