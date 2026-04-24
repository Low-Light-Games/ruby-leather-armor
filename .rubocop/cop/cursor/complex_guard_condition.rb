# frozen_string_literal: true

module RuboCop
  module Cop
    module Cursor
      class ComplexGuardCondition < Base
        MSG = "Extract complex guard conditions into a named helper method.".freeze
        MAX_LOGICAL_OPERATORS = 2
        GUARD_KEYWORDS = %i[return next break raise].freeze

        def on_if(node)
          return unless target_file?
          return unless node.modifier_form?
          return unless guard_clause?(node)
          return unless logical_operator_count(node.condition) > MAX_LOGICAL_OPERATORS

          add_offense(node.condition)
        end

        private

        def target_file?
          file_path = processed_source.file_path
          file_path.include?("/app/controllers/") || file_path.include?("/app/services/")
        end

        def guard_clause?(node)
          guard_expression?(node.if_branch) || guard_expression?(node.else_branch)
        end

        def guard_expression?(branch)
          return false unless branch

          branch.send_type? && GUARD_KEYWORDS.include?(branch.method_name)
        end

        def logical_operator_count(node)
          return 0 unless node
          return 0 unless node.and_type? || node.or_type?

          1 + logical_operator_count(node.lhs) + logical_operator_count(node.rhs)
        end
      end
    end
  end
end
