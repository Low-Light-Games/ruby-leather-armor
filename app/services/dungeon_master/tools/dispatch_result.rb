# frozen_string_literal: true

module DungeonMaster
  module Tools
    class DispatchResult
      attr_reader :request_roll_result

      def initialize(request_roll_result: nil)
        @request_roll_result = request_roll_result
      end

      def any?
        !@request_roll_result.nil?
      end
    end
  end
end
