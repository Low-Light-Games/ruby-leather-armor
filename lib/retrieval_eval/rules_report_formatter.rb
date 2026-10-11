# frozen_string_literal: true

module RetrievalEval
  # Plain-text tables for a RulesReport.
  class RulesReportFormatter
    LABELS = { hit_at_1: "hit@1", recall_at_k: "recall@%d", mrr: "MRR" }.freeze

    def initialize(report)
      @report = report
      @k = report.cutoff
    end

    def to_s
      [header, dev_table, test_table, difference_table, breakdown_tables, footer].flatten.join("\n")
    end

    private

    attr_reader :report, :k

    def label(metric)
      format(LABELS.fetch(metric), k)
    end

    def header
      counts = report.counts
      [
        "Rules retrieval eval: #{counts[:total]} queries, #{report.model}, cut-off k=#{k}",
        "  source: #{tally(counts[:by_source])}   slice: #{tally(counts[:by_slice])}",
        "  split (seed #{RulesEval::SPLIT_SEED}, stratified by slice x source): " \
        "dev #{counts[:dev]}, test #{counts[:test]} (#{tally(counts[:test_by_slice])})",
        "  CIs: 95% percentile bootstrap, #{Stats::DEFAULT_RESAMPLES} paired resamples, seed #{Stats::DEFAULT_SEED}",
        ""
      ]
    end

    def dev_table
      dev = report.metrics(report.dev)
      lines = ["DEV (#{report.dev.size} queries): used only to pick a variant",
               format("  %-14s %8s %10s %8s", "mode", label(:hit_at_1), label(:recall_at_k), label(:mrr))]
      dev.each do |mode, m|
        marker = mode == report.chosen_variant ? "  <- picked" : ""
        lines << format("  %-14s %8.3f %10.3f %8.3f%s", mode, m[:hit_at_1], m[:recall_at_k], m[:mrr], marker)
      end
      lines << "  picked: #{report.chosen_variant || 'none (no variant beats vector on dev)'}"
      lines << ""
    end

    def test_table
      lines = ["TEST (#{report.test.size} queries)",
               format("  %-14s %-21s %-21s %-21s", "mode", label(:hit_at_1), label(:recall_at_k), label(:mrr))]
      report.test_stats.each do |mode, stats|
        cells = RulesReport::METRICS.map { |metric| interval(stats[:metrics][metric], signed: false) }
        lines << format("  %-14s %-21s %-21s %-21s", mode, *cells)
      end
      lines << ""
    end

    def difference_table
      lines = ["TEST: mode minus vector (paired bootstrap CI); McNemar exact on hit@1 " \
               "(b = only vector right, c = only mode right; Holm across #{report.modes.size - 1} modes)",
               format("  %-14s %-23s %-23s %-23s %7s %7s %7s", "mode", "d #{label(:hit_at_1)}",
                      "d #{label(:recall_at_k)}", "d #{label(:mrr)}", "b/c", "p", "p_holm")]
      report.test_stats.each do |mode, stats|
        next unless stats[:difference]

        cells = RulesReport::METRICS.map { |metric| interval(stats[:difference][metric], signed: true) }
        mcnemar = stats[:mcnemar]
        lines << format("  %-14s %-23s %-23s %-23s %7s %7.3f %7.3f", mode, *cells,
                        "#{mcnemar[:b]}/#{mcnemar[:c]}", mcnemar[:p], mcnemar[:p_holm])
      end
      lines << ""
    end

    def breakdown_tables
      %i[slice source].flat_map do |attribute|
        report.breakdown(attribute).flat_map do |group, data|
          lines = ["TEST by #{attribute} = #{group} (#{data[:n]} queries)",
                   format("  %-14s %8s %10s %8s", "mode", label(:hit_at_1), label(:recall_at_k), label(:mrr))]
          data[:metrics].each do |mode, m|
            lines << format("  %-14s %8.3f %10.3f %8.3f", mode, m[:hit_at_1], m[:recall_at_k], m[:mrr])
          end
          lines << ""
        end
      end
    end

    def footer
      detection = report.jargon_detection
      [
        "Router heuristic vs slice tag (all queries): " \
        "#{detection.map { |(tag, detected), n| "#{tag}->#{detected}: #{n}" }.sort.join(', ')}",
        "fallback (keyword only when embedding fails) = vector whenever embedding succeeds; " \
        "in an outage it is keyword.",
        "",
        "Verdict: #{report.verdict}"
      ]
    end

    def interval(stat, signed:)
      number = signed ? "%+.3f [%+.2f, %+.2f]" : "%.3f [%.2f, %.2f]"
      format(number, stat[:mean], *stat[:ci])
    end

    def tally(hash)
      hash.sort.map { |key, n| "#{key} #{n}" }.join(", ")
    end
  end
end
