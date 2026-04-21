# frozen_string_literal: true

module RuboCop
  module Cop
    module Cursor
      # Enforces a blank line after one-line guard clauses.
      #
      # Example:
      #   return unless condition
      #
      #   do_work
      class BlankLineAfterGuardClause < Base
        extend AutoCorrector
        include RangeHelp

        MSG = "Add a blank line after guard clauses.".freeze
        GUARD_REGEX = /^\s*(return|next|break|raise)\b.*\b(if|unless)\b/.freeze

        def on_new_investigation
          lines = processed_source.lines

          lines.each_with_index do |line, index|
            next unless guard_clause_line?(line)

            next_index = index + 1
            next if next_index >= lines.length

            next_line = lines[next_index]
            next_nonempty_index = find_next_nonempty_line_index(lines, next_index)
            next if next_nonempty_index.nil?

            next if lines[next_nonempty_index].strip == "end"

            next if next_line.strip.empty?

            line_range = range_by_whole_lines(
              source_range(processed_source.buffer, index + 1, 0),
              include_final_newline: false
            )
            add_offense(line_range) do |corrector|
              corrector.insert_after(line_range, "\n")
            end
          end
        end

        private

        def guard_clause_line?(line)
          line.match?(GUARD_REGEX)
        end

        def find_next_nonempty_line_index(lines, starting_index)
          lines.each_index.drop(starting_index).find { |line_index| lines[line_index].strip != "" }
        end
      end
    end
  end
end
