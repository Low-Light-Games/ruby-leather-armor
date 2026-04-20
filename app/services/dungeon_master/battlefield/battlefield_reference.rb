# frozen_string_literal: true

module DungeonMaster
  module Battlefield
    class BattlefieldReference
      attr_reader :id, :version, :topology

      def self.from_battlefield(battlefield)
        new(id: battlefield.id, version: battlefield.version, topology: battlefield.topology)
      end

      def self.from_hash(reference_hash)
        return nil unless reference_hash.is_a?(Hash)

        reference = new(
          id: reference_hash["id"] || reference_hash[:id],
          version: reference_hash["version"] || reference_hash[:version],
          topology: reference_hash["topology"] || reference_hash[:topology]
        )
        reference.valid? ? reference : nil
      end

      def initialize(id:, version:, topology:)
        @id = id.to_i if id.present?
        @version = version.to_i if version.present?
        @topology = topology.to_s if topology.present?
      end

      def valid?
        id.present?
      end

      def to_h
        {
          "id" => id,
          "version" => version,
          "topology" => topology
        }.compact
      end
    end
  end
end
