class AddCallTypeToAiUsageRecords < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_usage_records, :call_type, :string
    add_index :ai_usage_records, :call_type
  end
end
