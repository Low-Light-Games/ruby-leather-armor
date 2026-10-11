# frozen_string_literal: true

module Retrieval
  # Reciprocal Rank Fusion (Cormack et al., 2009). Uses ranks only, so a cosine
  # list and a ts_rank list merge without calibrating either score.
  module ReciprocalRankFusion
    DEFAULT_K = 60

    def self.fuse(*rankings, k: DEFAULT_K, weights: nil)
      weights ||= Array.new(rankings.size, 1)
      raise ArgumentError, "one weight per ranking" unless weights.size == rankings.size

      scores = Hash.new(0.0)
      rankings.zip(weights).each do |ranking, weight|
        ranking.uniq.each_with_index { |id, index| scores[id] += weight.to_f / (k + index + 1) }
      end

      scores.sort_by.with_index { |(_id, score), seen| [-score, seen] }
    end
  end
end
