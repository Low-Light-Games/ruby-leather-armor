# frozen_string_literal: true

class Currency
  KEYS = %w[gold silver copper platinum].freeze

  GP_RATES = {
    "platinum" => 10.0,
    "gold"     => 1.0,
    "silver"   => 0.1,
    "copper"   => 0.01,
  }.freeze

  def initialize(hash = {})
    raw = hash.is_a?(Hash) ? hash : {}
    @data = KEYS.each_with_object({}) { |k, h| h[k] = raw[k].to_i }
    @data.freeze
  end

  def self.zero
    new({})
  end

  def gold     = @data["gold"]
  def silver   = @data["silver"]
  def copper   = @data["copper"]
  def platinum = @data["platinum"]

  def total_coins
    @data.values.sum
  end

  def total_gp_value
    GP_RATES.sum { |k, rate| @data[k] * rate }
  end

  def zero?
    @data.values.all?(&:zero?)
  end

  def add(other)
    Currency.new(KEYS.each_with_object({}) { |k, h| h[k] = @data[k] + other.send(k) })
  end

  def subtract(other)
    Currency.new(KEYS.each_with_object({}) { |k, h| h[k] = @data[k] - other.send(k) })
  end

  def to_h
    @data.dup
  end

  def ==(other)
    other.is_a?(Currency) && to_h == other.to_h
  end

  def inspect
    "#<Currency gold=#{gold} silver=#{silver} copper=#{copper} platinum=#{platinum}>"
  end
end
