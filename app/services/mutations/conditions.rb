# frozen_string_literal: true

module Mutations
  class Conditions
    def self.apply(sheet:, add:, remove:, log:)
      current = Transformers::CoercedMutationArray.coerce(sheet.conditions, field: "sheet.conditions", log: log).dup
      changed = false

      Transformers::CoercedMutationArray.coerce(remove, field: "conditions_remove", log: log).each do |cond|
        next unless CharacterStats::Conditions.valid?(cond)

        changed = true if current.delete(cond)
      end

      Transformers::CoercedMutationArray.coerce(add, field: "conditions_add", log: log).each do |cond|
        next unless CharacterStats::Conditions.valid?(cond)

        current = CharacterStats::Conditions.upgrade(current, cond)
        changed = true
      end

      sheet.update!(conditions: current.uniq) if changed
      changed
    end
  end
end
