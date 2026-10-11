# frozen_string_literal: true

module RetrievalEval
  # Small, dependency-free statistics for the retrieval evals.
  #
  # Paired bootstrap: every call with the same `n`, `seed` and `resamples`
  # draws the same resampled query indices, so CIs for two modes (and for their
  # per-query difference) are computed on identical resamples.
  module Stats
    DEFAULT_RESAMPLES = 10_000
    DEFAULT_SEED = 2026

    module_function

    def mean(values)
      return 0.0 if values.empty?

      values.sum.to_f / values.size
    end

    # Percentile bootstrap CI of the mean: [low, high].
    def bootstrap_ci(values, resamples: DEFAULT_RESAMPLES, seed: DEFAULT_SEED, confidence: 0.95)
      return [0.0, 0.0] if values.empty?

      means = resample_indices(values.size, resamples, seed).map do |indices|
        indices.sum { |i| values[i] }.to_f / values.size
      end.sort
      tail = (1 - confidence) / 2
      [percentile(means, tail), percentile(means, 1 - tail)]
    end

    # Paired bootstrap CI of mean(a) - mean(b), resampling queries (pairs).
    def paired_difference_ci(a, b, **)
      raise ArgumentError, "paired samples must have the same length" unless a.size == b.size

      bootstrap_ci(a.zip(b).map { |x, y| x - y }, **)
    end

    # Exact (binomial) two-sided McNemar test on paired binary outcomes.
    # b = pairs where only the first system succeeds, c = only the second.
    def mcnemar_exact(b, c)
      n = b + c
      return 1.0 if n.zero?

      tail = (0..[b, c].min).sum { |i| binomial(n, i) }
      [Rational(2 * tail, 2**n), 1].min.to_f
    end

    # Discordant counts for McNemar from two arrays of 0/1 outcomes.
    def discordant(a, b)
      raise ArgumentError, "paired samples must have the same length" unless a.size == b.size

      pairs = a.zip(b)
      [pairs.count { |x, y| x.positive? && y.zero? }, pairs.count { |x, y| x.zero? && y.positive? }]
    end

    # Holm-Bonferroni adjusted p-values, in the input order.
    def holm(p_values)
      m = p_values.size
      running = 0.0
      adjusted = Array.new(m)
      p_values.each_with_index.sort_by(&:first).each_with_index do |(p, index), rank|
        running = ((m - rank) * p).clamp(running, 1.0)
        adjusted[index] = running
      end
      adjusted
    end

    # Linear interpolation between closest ranks (R type 7).
    def percentile(sorted, q)
      position = q * (sorted.size - 1)
      lower = sorted[position.floor]
      upper = sorted[position.ceil]
      lower + ((upper - lower) * (position - position.floor))
    end

    def binomial(n, k)
      (1..k).reduce(1) { |acc, i| acc * (n - k + i) / i }
    end

    def resample_indices(n, resamples, seed)
      @resample_cache ||= {}
      @resample_cache[[n, resamples, seed]] ||= begin
        rng = Random.new(seed)
        Array.new(resamples) { Array.new(n) { rng.rand(n) } }.freeze
      end
    end
  end
end
