# frozen_string_literal: true

module Onboarding
  class SheetBlueprint
    SHEET_ATTRIBUTE_KEYS = %i[
      name description character_class level race strength dexterity constitution intelligence wisdom charisma currency
    ].freeze

    def initialize(raw_data)
      @raw_data = raw_data
    end

    def sheet_attributes
      @sheet_attributes ||= SHEET_ATTRIBUTE_KEYS.index_with { |key| @raw_data[key] }
    end

    def feat_names
      Array(@raw_data[:feat_names])
    end

    def item_names
      Array(@raw_data[:item_names])
    end
  end
end
