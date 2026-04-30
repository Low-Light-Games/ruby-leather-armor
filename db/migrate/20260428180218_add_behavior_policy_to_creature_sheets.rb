class AddBehaviorPolicyToCreatureSheets < ActiveRecord::Migration[7.1]
  def change
    add_column :creature_sheets, :behavior_policy, :jsonb, null: false, default: {}
  end
end
