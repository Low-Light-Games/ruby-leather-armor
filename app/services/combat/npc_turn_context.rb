# frozen_string_literal: true

module Combat
  # Bundled inputs passed between Combat::NpcTurn helpers — keeps each
  # helper's signature small and gives the bundle a name that surfaces
  # in stack traces. Pure value object; no behavior beyond exposing
  # the fields it carries.
  class NpcTurnContext
    attr_reader :creature, :adventure, :target_sheet, :policy, :npc_pos, :target_pos

    def initialize(actors:, world:)
      @creature = actors[:creature]
      @target_sheet = actors[:target_sheet]
      @policy = actors[:policy]
      @adventure = world[:adventure]
      @npc_pos = world[:npc_pos]
      @target_pos = world[:target_pos]
    end
  end
end
