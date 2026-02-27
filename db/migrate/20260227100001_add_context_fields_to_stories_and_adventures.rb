# frozen_string_literal: true

class AddContextFieldsToStoriesAndAdventures < ActiveRecord::Migration[7.1]
  def change
    add_column :stories, :initial_context, :text

    add_column :adventures, :immediate_context, :text
    add_column :adventures, :story_summary, :text
  end
end
