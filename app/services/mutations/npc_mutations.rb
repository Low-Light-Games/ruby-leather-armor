# frozen_string_literal: true

module Mutations
  class NpcMutations
    def initialize(adventure:, log:)
      @adventure = adventure
      @log = log
    end

    def call(npc_muts)
      lines = []

      Transformers::CoercedMutationArray.coerce(npc_muts, field: "npcs", log: @log).each do |npc_mut|
        npc_mut  = npc_mut.deep_symbolize_keys if npc_mut.is_a?(Hash)
        creature = resolve_adventure_actor_sheet(npc_mut)
        next unless creature

        name = creature.name

        hp_change = npc_mut[:hp_change]
        if hp_change.to_i != 0
          old_hp = creature.hp
          new_hp = (old_hp + hp_change.to_i).clamp(0, creature.max_hp)
          creature.update!(hp: new_hp)
          lines << "#{name}: HP #{old_hp} → #{new_hp} (#{new_hp >= old_hp ? '+' : ''}#{new_hp - old_hp})" if new_hp != old_hp
        end

        attitude = npc_mut[:attitude_change]
        if attitude.is_a?(Hash)
          new_attitude = attitude[:to]
          if new_attitude && AdventureActorSheet::ATTITUDES.include?(new_attitude)
            old_attitude = creature.attitude
            creature.update!(attitude: new_attitude)
            lines << "#{name}: attitude → #{new_attitude}" if new_attitude != old_attitude
          end
        end

        conditions_before = Array(creature.conditions).dup
        conditions_changed = Conditions.apply(
          sheet: creature,
          add: npc_mut[:conditions_add],
          remove: npc_mut[:conditions_remove],
          log: @log
        )
        if conditions_changed
          conditions_after = Array(creature.conditions)
          (conditions_after - conditions_before).each { |c| lines << "#{name}: condition gained — #{c}" }
          (conditions_before - conditions_after).each { |c| lines << "#{name}: condition removed — #{c}" }
        end

        creature.recompute_derived_stats! if conditions_changed
      end

      lines
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
