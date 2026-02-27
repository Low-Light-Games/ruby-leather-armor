# frozen_string_literal: true

class AddRequestBodyToAiLogs < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_logs, :request_body, :text
  end
end
