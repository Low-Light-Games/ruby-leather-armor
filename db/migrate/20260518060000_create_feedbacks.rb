# frozen_string_literal: true

class CreateFeedbacks < ActiveRecord::Migration[7.1]
  def change
    create_table :feedbacks do |t|
      t.references :user, null: true, foreign_key: true
      t.text       :body,      null: false
      t.string     :page_url
      t.string     :user_agent

      t.timestamps
    end
  end
end
