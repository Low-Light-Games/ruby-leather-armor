# frozen_string_literal: true

module DungeonMaster
  module Battlefield
    module BattlefieldRef
      module_function

      def valid_reference?(reference)
        reference.is_a?(Hash) && reference["id"].present?
      end

      def reference_id(reference)
        return nil unless valid_reference?(reference)

        reference["id"].to_i
      end

      def build_from_battlefield(battlefield)
        {
          "id" => battlefield.id,
          "version" => battlefield.version,
          "topology" => battlefield.topology
        }
      end

      def attach_to_combat_context(combat_context, battlefield:)
        updated_context = combat_context.deep_dup.deep_stringify_keys
        updated_context["battlefield_ref"] = build_from_battlefield(battlefield)
        updated_context
      end

      def clear_from_combat_context(combat_context)
        updated_context = combat_context.deep_dup.deep_stringify_keys
        updated_context.delete("battlefield_ref")
        updated_context
      end
    end
  end
end
