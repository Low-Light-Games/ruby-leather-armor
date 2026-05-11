# frozen_string_literal: true

module Battlefield
  module CombatContextReferencePatch
    module_function

    def reference_from(combat_context)
      BattlefieldReference.from_hash(normalized_combat_context(combat_context)["battlefield_ref"])
    end

    def attach(combat_context, battlefield:)
      updated_context = normalized_combat_context(combat_context)
      updated_context["battlefield_ref"] = BattlefieldReference.from_battlefield(battlefield).to_h
      updated_context
    end

    def clear(combat_context)
      updated_context = normalized_combat_context(combat_context)
      updated_context.delete("battlefield_ref")
      updated_context
    end

    def normalized_combat_context(combat_context)
      (combat_context || {}).deep_dup.deep_stringify_keys
    end
    private_class_method :normalized_combat_context
  end
end
