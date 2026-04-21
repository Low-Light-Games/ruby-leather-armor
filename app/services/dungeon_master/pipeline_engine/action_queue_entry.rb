# frozen_string_literal: true

module DungeonMaster
  class PipelineEngine
    class ActionQueueEntry
      attr_reader :text, :depends_on_index, :prerequisite, :abort_on_failed_prerequisite

      def self.from_unknown(raw_entry)
        case raw_entry
        when String
          new(
            text: raw_entry,
            depends_on_index: nil,
            prerequisite: nil,
            abort_on_failed_prerequisite: false
          )
        when Hash
          text = (raw_entry["text"] || raw_entry[:text]).to_s
          return nil if text.blank?

          new(
            text: text,
            depends_on_index: raw_entry["depends_on_index"] || raw_entry[:depends_on_index],
            prerequisite: raw_entry["prerequisite"] || raw_entry[:prerequisite],
            abort_on_failed_prerequisite: (raw_entry["abort_on_failed_prerequisite"] || raw_entry[:abort_on_failed_prerequisite]) == true
          )
        end
      end

      def initialize(text:, depends_on_index:, prerequisite:, abort_on_failed_prerequisite:)
        @text = text.to_s
        @depends_on_index = depends_on_index
        @prerequisite = prerequisite.present? ? prerequisite.to_s : nil
        @abort_on_failed_prerequisite = abort_on_failed_prerequisite == true
      end

      def to_h
        {
          "text" => text,
          "depends_on_index" => depends_on_index,
          "prerequisite" => prerequisite,
          "abort_on_failed_prerequisite" => abort_on_failed_prerequisite
        }
      end
    end
  end
end
