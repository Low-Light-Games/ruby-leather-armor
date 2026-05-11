# frozen_string_literal: true

# Shared currency helpers for Sheet, AdventureSheet, and AdventureActorSheet.
#
# All three store currency in a JSONB column with the same schema:
#   { "gold" => N, "silver" => N, "copper" => N, "platinum" => N }
#
# Including this concern eliminates the duplicated CURRENCY_KEYS constant
# and total_coins / total_gp_value implementations across those models.
module SheetCurrency
  extend ActiveSupport::Concern

  included do
    # Kept for any callers that reference Model::CURRENCY_KEYS directly.
    CURRENCY_KEYS = Currency::KEYS
  end

  def currency_value
    Currency.new(currency)
  end

  def total_coins
    currency_value.total_coins
  end

  def total_gp_value
    currency_value.total_gp_value
  end
end
