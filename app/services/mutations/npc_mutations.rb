# frozen_string_literal: true

module Mutations
  class NpcMutations
    def initialize(adventure:, log:)
      @adventure = adventure
      @log = log
    end

    def call(npc_muts)
      Transformers::CoercedMutationArray.coerce(npc_muts, field: "npcs", log: @log).each do |npc_mut|
        npc_mut  = npc_mut.deep_symbolize_keys if npc_mut.is_a?(Hash)
        creature = resolve_adventure_actor_sheet(npc_mut)
        next unless creature

        hp_change = npc_mut[:hp_change]
        if hp_change.to_i != 0
          new_hp = (creature.hp + hp_change.to_i).clamp(0, creature.max_hp)
          creature.update!(hp: new_hp)
        end

        attitude = npc_mut[:attitude_change]
        if attitude.is_a?(Hash)
          new_attitude = attitude[:to]
          creature.update!(attitude: new_attitude) if new_attitude && AdventureActorSheet::ATTITUDES.include?(new_attitude)
        end

        conditions_changed = Conditions.apply(
          sheet: creature,
          add: npc_mut[:conditions_add],
          remove: npc_mut[:conditions_remove],
          log: @log
        )
        creature.recompute_derived_stats! if conditions_changed
      end
    end

    private

    def resolve_adventure_actor_sheet(npc_mut)
      sid = npc_mut[:actor_sheet_id]
      if sid.present?
        @adventure.adventure_actor_sheets.find_by(id: sid.to_i)
      elsif npc_mut[:name].present?
        @adventure.adventure_actor_sheets.find_by(name: npc_mut[:name].to_s)
      end
    end
  end
end
