# frozen_string_literal: true

module Contextable
  extend ActiveSupport::Concern

  CONTEXT_FIELDS = %w[combat_context time_context].freeze

  def merge_context!(field, updates)
    col = context_column_name(field)
    current = public_send(col) || {}
    update!(col => current.merge(updates))
  end

  def reset_context!(field)
    update!(context_column_name(field) => {})
  end

  private

  def context_column_name(field)
    col = field.to_s.end_with?("_context") ? field.to_s : "#{field}_context"
    unless CONTEXT_FIELDS.include?(col)
      raise ArgumentError, "Unknown context field: #{col.inspect}. " \
                           "Valid fields: #{CONTEXT_FIELDS.join(', ')}"
    end
    col
  end
end
