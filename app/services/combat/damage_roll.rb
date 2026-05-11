# frozen_string_literal: true

module Combat
  class DamageRoll
    attr_reader :total, :type

    # @param total [Integer]
    # @param type [String, nil]
    def initialize(total:, type:)
      @total = total
      @type = type
    end

    def to_h
      { total: total, type: type }
    end

    def [](key)
      to_h[key]
    end

    def fetch(key, *defaults)
      to_h.fetch(key, *defaults)
    end
  end
end
