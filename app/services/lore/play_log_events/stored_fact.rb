# frozen_string_literal: true

module Lore
  module PlayLogEvents
    class StoredFact
      TEXT_PREVIEW_LENGTH = 200

      attr_reader :fact_id, :kind, :polarity, :source, :source_idx, :text

      def initialize(fact_id:, kind:, polarity:, source:, source_idx:, text:)
        @fact_id    = fact_id
        @kind       = kind
        @polarity   = polarity
        @source     = source
        @source_idx = source_idx
        @text       = text.to_s
      end

      def to_h
        {
          fact_id:    @fact_id,
          kind:       @kind,
          polarity:   @polarity,
          source:     @source,
          source_idx: @source_idx,
          text:       truncate(@text),
        }
      end

      private

      def truncate(text)
        text.length > TEXT_PREVIEW_LENGTH ? "#{text.first(TEXT_PREVIEW_LENGTH)}…" : text
      end
    end
  end
end
