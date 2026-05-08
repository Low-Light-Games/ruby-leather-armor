# frozen_string_literal: true

module Battlefield
  class PatchState
    attr_reader :tokens, :viewport, :world

    def self.from_battlefield(battlefield)
      new(
        tokens: battlefield.tokens.deep_dup,
        viewport: battlefield.viewport.deep_dup,
        world: battlefield.world.deep_dup
      )
    end

    def initialize(tokens:, viewport:, world:)
      @tokens = tokens
      @viewport = viewport
      @world = world
    end

    def to_h
      {
        "tokens" => tokens,
        "viewport" => viewport,
        "world" => world
      }
    end
  end
end
