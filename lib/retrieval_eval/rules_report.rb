# frozen_string_literal: true

module RetrievalEval
  # Scores and reports a RulesEval run.
  #
  # Metrics per query, averaged per mode:
  #   hit@1    - the top result is one of the labelled rules
  #   recall@k - share of labelled rules inside the top k (what the prompt sees)
  #   mrr      - 1 / rank of the first labelled rule (0 if absent)
  #
  # Protocol, fixed before looking at results:
  #   1. On dev only, pick at most one variant: the one with the best
  #      (recall@k, mrr, hit@1), and only if that beats vector's on dev.
  #   2. On test, report every mode with 95% bootstrap CIs (paired resamples,
  #      fixed seed), the paired-bootstrap CI of its difference from vector,
  #      and McNemar's exact test on hit@1 (Holm-adjusted across modes).
  #   3. The picked variant clearly wins only if its recall@k difference CI on
  #      test is entirely above zero and hit@1 is not significantly worse.
  class RulesReport
    METRICS = %i[hit_at_1 recall_at_k mrr].freeze
    BASELINE = :vector
    ALPHA = 0.05

    attr_reader :results, :cutoff, :model

    def initialize(results, cutoff:, model:)
      @results = results
      @cutoff = cutoff
      @model = model
    end

    def modes
      results.first[:rankings].keys
    end

    def dev
      @dev ||= results.select { |r| r[:split] == :dev }
    end

    def test
      @test ||= results.select { |r| r[:split] == :test }
    end

    # Point metrics per mode over a set of results (all queries by default).
    def metrics(subset = results)
      modes.index_with do |mode|
        METRICS.index_with { |metric| Stats.mean(values(subset, mode, metric)) }
      end
    end

    # The variant picked on dev, or nil when none beats vector there.
    def chosen_variant
      return @chosen_variant if defined?(@chosen_variant)

      dev_metrics = metrics(dev)
      key = ->(mode) { dev_metrics[mode].values_at(:recall_at_k, :mrr, :hit_at_1) }
      best = (modes - [BASELINE, :keyword]).max_by { |mode| [key.call(mode), -modes.index(mode)] }
      @chosen_variant = (key.call(best) <=> key.call(BASELINE)).positive? ? best : nil
    end

    # Test-set statistics per mode: mean and CI per metric, plus, for every
    # mode other than vector, the difference from vector and McNemar on hit@1.
    def test_stats
      @test_stats ||= begin
        stats = modes.index_with { |mode| mode_stats(mode) }
        others = modes - [BASELINE]
        holm = Stats.holm(others.map { |mode| stats[mode][:mcnemar][:p] })
        others.each_with_index { |mode, i| stats[mode][:mcnemar][:p_holm] = holm[i] }
        stats
      end
    end

    def verdict
      mode = chosen_variant
      return "No variant beat vector on dev; nothing to test. Production stays vector-only." unless mode

      stats = test_stats[mode]
      low, = stats[:difference][:recall_at_k][:ci]
      worse_hit = stats[:mcnemar][:b] > stats[:mcnemar][:c] && stats[:mcnemar][:p] < ALPHA
      if low.positive? && !worse_hit
        "#{mode} beats vector on test: recall@#{cutoff} difference CI excludes zero."
      else
        "#{mode} does not clearly beat vector on test (recall@#{cutoff} difference CI includes zero" \
          "#{' or hit@1 is significantly worse' if worse_hit}). Production stays vector-only."
      end
    end

    def jargon_detection
      results.map { |r| [r[:slice], r[:jargon_detected] ? "jargon" : "paraphrase"] }.tally
    end

    def to_s
      RulesReportFormatter.new(self).to_s
    end

    def as_json(*)
      {
        model: model, cutoff: cutoff, resamples: Stats::DEFAULT_RESAMPLES, bootstrap_seed: Stats::DEFAULT_SEED,
        split_seed: RulesEval::SPLIT_SEED, counts: counts, chosen_variant: chosen_variant, verdict: verdict,
        dev: metrics(dev), test: test_stats,
        test_by_slice: breakdown(:slice), test_by_source: breakdown(:source),
        queries: results.map { |r| r.slice(:text, :relevant, :source, :slice, :split, :jargon_detected, :rankings) }
      }
    end

    def counts
      {
        total: results.size, dev: dev.size, test: test.size,
        by_source: results.map { |r| r[:source] }.tally, by_slice: results.map { |r| r[:slice] }.tally,
        test_by_source: test.map { |r| r[:source] }.tally, test_by_slice: test.map { |r| r[:slice] }.tally
      }
    end

    # {group value => {n:, metrics: {mode => {metric => mean}}}} on test.
    def breakdown(attribute)
      test.group_by { |r| r[attribute] }.sort.to_h.transform_values do |subset|
        { n: subset.size, metrics: metrics(subset) }
      end
    end

    def values(subset, mode, metric)
      subset.map { |r| score(r, mode, metric) }
    end

    private

    def mode_stats(mode)
      stats = { metrics: METRICS.index_with { |metric| summary(values(test, mode, metric)) } }
      return stats if mode == BASELINE

      stats[:difference] = METRICS.index_with do |metric|
        a = values(test, mode, metric)
        b = values(test, BASELINE, metric)
        { mean: Stats.mean(a) - Stats.mean(b), ci: Stats.paired_difference_ci(a, b) }
      end
      only_baseline, only_mode = Stats.discordant(values(test, BASELINE, :hit_at_1), values(test, mode, :hit_at_1))
      stats[:mcnemar] = { b: only_baseline, c: only_mode, p: Stats.mcnemar_exact(only_baseline, only_mode) }
      stats
    end

    def summary(values)
      { mean: Stats.mean(values), ci: Stats.bootstrap_ci(values) }
    end

    def score(result, mode, metric)
      ranking = result[:rankings].fetch(mode)
      relevant = result[:relevant]
      case metric
      when :hit_at_1 then relevant.include?(ranking.first) ? 1.0 : 0.0
      when :recall_at_k then (ranking.first(cutoff) & relevant).size.fdiv(relevant.size)
      when :mrr
        index = ranking.index { |slug| relevant.include?(slug) }
        index ? 1.0 / (index + 1) : 0.0
      end
    end
  end
end
