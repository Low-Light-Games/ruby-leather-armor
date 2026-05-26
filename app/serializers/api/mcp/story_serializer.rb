# frozen_string_literal: true

module Api
  module Mcp
    class StorySerializer
      def self.call(story, include_text: false)
        base = {
          id: story.id,
          title: story.title,
          preview: story.preview,
          world_terrain: story.world_terrain,
          hidden_from_players: story.hidden_from_players,
          discarded_at: story.discarded_at,
          created_at: story.created_at,
          updated_at: story.updated_at
        }
        base.merge!(premise: story.premise, opening_message: story.opening_message) if include_text
        base
      end
    end
  end
end
