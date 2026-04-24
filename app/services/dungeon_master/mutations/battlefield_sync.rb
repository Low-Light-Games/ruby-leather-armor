# frozen_string_literal: true

module DungeonMaster
  module Mutations
    class BattlefieldSync
      def self.apply!(mutations, adventure:, log:)
        patches = mutations[:battlefield_patches]
        return if patches.blank?

        Battlefield::ApplyPatches.call(adventure: adventure, patches: patches, log: log)
      end
    end
  end
end
