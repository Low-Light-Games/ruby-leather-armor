# frozen_string_literal: true

module Combat
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
