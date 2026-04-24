# frozen_string_literal: true

module RuboCop
  module Cop
    module Cursor
      class ServiceLiteralHashBoundary < Base
        MSG = "Extract large service hash payloads into named value objects, presenters, or serializers.".freeze
        MIN_PAIRS = 6
        EXCLUDED_METHOD_NAMES = %i[to_h as_json serializable_hash].freeze

        def on_hash(node)
          return unless target_service_file?
          return unless boundary_hash?(node)
          return unless node.pairs.length >= MIN_PAIRS

          add_offense(node)
        end

        private

        def target_service_file?
          processed_source.file_path.include?("/app/services/")
        end

        def boundary_hash?(node)
          assigned_hash?(node) || returned_hash?(node)
        end

        def assigned_hash?(node)
          parent = node.parent
          parent&.lvasgn_type? || parent&.ivasgn_type? || parent&.cvasgn_type?
        end

        def returned_hash?(node)
          parent = node.parent
          return false unless parent&.send_type?
          return false unless parent.receiver.nil?

          parent.method?(:return) && !inside_serializer_method?(node)
        end

        def inside_serializer_method?(node)
          node.each_ancestor(:def, :defs).any? { |ancestor| EXCLUDED_METHOD_NAMES.include?(ancestor.method_name) }
        end
      end
    end
  end
end
