# frozen_string_literal: true

module Retrieval
  # Reciprocal Rank Fusion (Cormack et al., 2009): score(d) = sum over the
  # rankings of 1 / (k + rank(d)). It only looks at ranks, so it can merge a
  # cosine-distance list with a ts_rank list without calibrating either score.
  # k = 60 is the value from the paper and the usual default.
  module ReciprocalRankFusion
    DEFAULT_K = 60

    # rankings: arrays of ids, best first. Returns [[id, score], ...], best
    # first; ties keep the order in which ids were first seen.
    def self.fuse(*rankings, k: DEFAULT_K)
      scores = Hash.new(0.0)
      rankings.each do |ranking|
        ranking.uniq.each_with_index { |id, index| scores[id] += 1.0 / (k + index + 1) }
      end

      scores.sort_by.with_index { |(_id, score), seen| [-score, seen] }
    end
  end
end
