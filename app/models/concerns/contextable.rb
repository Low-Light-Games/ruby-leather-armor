# frozen_string_literal: true

# Shared helpers for models that carry DM context JSONB fields.
#
# Currently included in Adventure, which stores per-category context state
# (combat, traversal, social, exploration, rest, inventory, time) as separate
# JSONB columns.  The AR attributes themselves are defined by the schema; this
# concern only adds convenience methods on top.
module Contextable
  extend ActiveSupport::Concern

  CONTEXT_FIELDS = %w[
    combat_context
    traversal_context
    social_context
    exploration_context
    rest_context
    inventory_context
    time_context
  ].freeze

  # Merges +updates+ into the named context field and persists the record.
  #
  #   adventure.merge_context!(:combat, { "round" => 3 })
  #   # equivalent to:
  #   # adventure.update!(combat_context: adventure.combat_context.merge("round" => 3))
  #
  # @param field [String, Symbol]  one of the CONTEXT_FIELDS names, with or
  #   without the _context suffix.
  # @param updates [Hash]
  def merge_context!(field, updates)
    col = context_column_name(field)
    current = public_send(col) || {}
    update!(col => current.merge(updates))
  end

  # Resets the named context field to an empty hash.
  #
  #   adventure.reset_context!(:combat)
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
