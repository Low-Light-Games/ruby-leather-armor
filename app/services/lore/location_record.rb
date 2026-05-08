# frozen_string_literal: true

module Lore
  class LocationRecord
    attr_reader :name, :description, :x, :y, :story_location_id

    def initialize(name:, description: "", x:, y:, story_location_id: nil)
      @name              = name.to_s.strip
      @description       = description.to_s
      @x                 = x.to_f
      @y                 = y.to_f
      @story_location_id = story_location_id
    end

    def embedding_text
      parts = [@name]
      parts << @description if @description.present?
      parts.reject(&:empty?).join(" — ")
    end

    def to_h
      {
        name:              @name,
        description:       @description,
        x:                 @x,
        y:                 @y,
        story_location_id: @story_location_id,
      }
    end

    def self.from_story_location(story_location, x:, y:)
      new(
        name:              story_location.name,
        description:       story_location.description.to_s,
        x:                 x,
        y:                 y,
        story_location_id: story_location.id,
      )
    end
  end
end
