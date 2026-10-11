# frozen_string_literal: true

module Retrieval
  # Reciprocal Rank Fusion (Cormack et al., 2009): score(d) = sum over the
  # rankings of 1 / (k + rank(d)). It only looks at ranks, so it can merge a
  # cosine-distance list with a ts_rank list without calibrating either score.
  # k = 60 is the value from the paper and the usual default.
  module ReciprocalRankFusion
    DEFAULT_K = 60

    # rankings: arrays of ids, best first. Returns [[id, score], ...], best
    # first; ties keep the order in which ids were first seen. `weights`
    # (one per ranking, default all 1) gives weighted RRF.
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
