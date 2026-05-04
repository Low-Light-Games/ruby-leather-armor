# frozen_string_literal: true

module DungeonMaster
  module SceneRetrieval
    module Bearing
      LABELS = %w[north northeast east southeast south southwest west northwest].freeze
      STEP_DEGREES = 360.0 / LABELS.size

      module_function

      def label(dx:, dy:)
        return "here" if dx.abs < 1e-3 && dy.abs < 1e-3

        angle_deg = ((Math.atan2(dx, dy) * 180.0 / Math::PI) + 360) % 360
        index = (((angle_deg + (STEP_DEGREES / 2)) / STEP_DEGREES).floor) % LABELS.size
        LABELS[index]
      end
    end
  end
end
