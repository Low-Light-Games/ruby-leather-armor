# frozen_string_literal: true

module RuboCop
  module Cop
    module Cursor
      class NoStructNew < Base
        MSG = "Do not declare ad hoc structures with Struct.new; extract a named value object class.".freeze

        def on_send(node)
          return unless node.method?(:new)
          return unless node.receiver&.const_type?
          return unless node.receiver.const_name == "Struct"

          add_offense(node.loc.selector)
        end
      end
    end
  end
end
