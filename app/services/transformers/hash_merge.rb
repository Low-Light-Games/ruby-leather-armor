# frozen_string_literal: true

module Transformers
  module HashMerge
    module_function

    def deep_merge_presence(base, overlay)
      return overlay if base.blank?

      return base if overlay.blank?

      base.deep_merge(overlay)
    end
  end
end
