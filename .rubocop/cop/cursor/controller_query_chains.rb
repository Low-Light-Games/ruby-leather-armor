# frozen_string_literal: true

module RuboCop
  module Cop
    module Cursor
      class ControllerQueryChains < Base
        MSG = "Extract long ActiveRecord query chains in controllers into scopes or query objects.".freeze
        QUERY_METHODS = %i[includes joins left_joins where where.not order group select pluck preload eager_load references reselect reorder distinct limit offset].freeze
        MAX_QUERY_METHODS = 3

        def on_send(node)
          return unless target_controller_file?
          return unless query_method?(node)
          return if query_method?(node.parent)

          query_methods = query_chain_methods(node)
          return unless query_methods.length > MAX_QUERY_METHODS

          add_offense(node)
        end

        private

        def target_controller_file?
          processed_source.file_path.include?("/app/controllers/")
        end

        def query_method?(node)
          node&.send_type? && QUERY_METHODS.include?(normalized_method_name(node))
        end

        def normalized_method_name(node)
          node.method?(:not) && query_method?(node.receiver) ? :"#{node.receiver.method_name}.not" : node.method_name
        end

        def query_chain_methods(node)
          methods = []
          current = node

          while query_method?(current)
            methods << normalized_method_name(current)
            current = current.receiver
          end

          methods
        end
      end
    end
  end
end
