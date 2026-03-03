# frozen_string_literal: true

module DungeonMaster
  # App-side game state logic: applies AI-determined mutations to player/NPC
  # sheets, resolves NPC dice rolls, and manages creature lifecycle
  # (bestiary lookup, HP rolling, sheet creation).
  module Mutations
    private

    def apply_mutations(mutations)
      return unless mutations.is_a?(Hash)

      apply_player_mutations(mutations["player"] || mutations[:player])
      apply_npc_mutations(mutations["npcs"] || mutations[:npcs])
    rescue => e
      @log.dm_log!("Mutation application error: #{e.message}")
    end

    def resolve_npc_actions(npc_actions)
      return "(no NPC actions)" if npc_actions.blank?

      player_ac = @sheet&.derived_stats&.dig("ac") || 10
      results = npc_actions.map do |action|
        roll = rand(1..20)
        modifier = (action[:modifier] || 0).to_i
        total = roll + modifier
        hit = total >= player_ac
        "#{action[:actor]} #{action[:action]} -> rolled #{roll} + #{modifier} = #{total} " \
          "vs AC #{player_ac}: #{hit ? 'HIT' : 'MISS'}"
      end

      results.join("\n")
    end

    def handle_new_creatures(creature_names)
      Array(creature_names).each do |name|
        next if @adventure.creature_sheets.exists?(name: name)

        bestiary = BestiaryEntry.find_by("LOWER(name) = ?", name.downcase) if defined?(BestiaryEntry)
        if bestiary
          create_creature_from_bestiary(bestiary, name)
        else
          @log.dm_log!("No bestiary match for '#{name}' — creature sheet not auto-created")
        end
      end
    rescue => e
      @log.dm_log!("Creature creation error: #{e.message}")
    end

    def apply_time_span_mutations(mutations)
      return unless mutations.is_a?(Hash)

      ts = mutations["time_span"] || mutations[:time_span]
      return unless ts.is_a?(Hash)

      hours = ts["hours_elapsed"] || ts[:hours_elapsed]
      span_type = ts["type"] || ts[:type]
      @log.dm_log!("TimeSpan mutation: type=#{span_type}, hours=#{hours}")

      if ts["arrived"] || ts[:arrived]
        new_loc_id = ts["new_location_id"] || ts[:new_location_id]
        if new_loc_id
          @adventure.update!(current_location_id: new_loc_id)
          @log.dm_log!("Location updated to id=#{new_loc_id}")
        end
      end

      traversal = (@adventure.traversal_context || {}).dup
      case span_type.to_s
      when "journey"
        dist = ts["distance_covered_miles"] || ts[:distance_covered_miles]
        destination = ts["destination"] || ts[:destination]
        traversal["last_travel_hours"] = hours
        traversal["last_travel_distance_miles"] = dist
        if ts["arrived"] || ts[:arrived]
          new_loc = StoryLocation.find_by(id: ts["new_location_id"] || ts[:new_location_id])
          traversal["current_location"] = new_loc&.name
          traversal["destination"] = nil
        else
          traversal["destination"] = destination
        end
      when "rest"
        traversal["last_rest_hours"] = hours
      end
      @adventure.update!(traversal_context: traversal)
    rescue => e
      @log.dm_log!("Time-span mutation error: #{e.message}")
    end

    # -- private helpers ------------------------------------------------

    def apply_player_mutations(player_muts)
      return unless player_muts && @sheet

      hp_change = player_muts["hp_change"] || player_muts[:hp_change]
      if hp_change.to_i != 0
        new_hp = (@sheet.hp + hp_change.to_i).clamp(-@sheet.constitution, @sheet.max_hp)
        @sheet.update!(hp: new_hp)
      end
    end

    def apply_npc_mutations(npc_muts)
      Array(npc_muts).each do |npc_mut|
        name = npc_mut["name"] || npc_mut[:name]
        creature = @adventure.creature_sheets.find_by(name: name)
        next unless creature

        hp_change = npc_mut["hp_change"] || npc_mut[:hp_change]
        if hp_change.to_i != 0
          new_hp = (creature.hp + hp_change.to_i).clamp(0, creature.max_hp)
          creature.update!(hp: new_hp)
        end

        attitude = npc_mut["attitude_change"] || npc_mut[:attitude_change]
        if attitude.is_a?(Hash)
          new_attitude = attitude["to"] || attitude[:to]
          creature.update!(attitude: new_attitude) if new_attitude && CreatureSheet::ATTITUDES.include?(new_attitude)
        end
      end
    end

    def create_creature_from_bestiary(entry, display_name)
      hp = roll_hp(entry.hp_formula)
      @adventure.creature_sheets.create!(
        name: display_name,
        creature_type: entry.creature_type || "npc",
        strength: entry.strength, dexterity: entry.dexterity, constitution: entry.constitution,
        intelligence: entry.intelligence, wisdom: entry.wisdom, charisma: entry.charisma,
        level: [entry.cr.to_i, 1].max,
        hp: hp, max_hp: hp,
        derived_stats: { "ac" => entry.ac, "bab" => entry.base_attack, "speed" => entry.speed }
      )
    end

    def roll_hp(formula)
      return 10 unless formula.present?

      if formula =~ /(\d+)d(\d+)([+-]\d+)?/
        count, die, mod = $1.to_i, $2.to_i, ($3 || 0).to_i
        count.times.sum { rand(1..die) } + mod
      else
        formula.to_i.nonzero? || 10
      end
    end
  end
end
