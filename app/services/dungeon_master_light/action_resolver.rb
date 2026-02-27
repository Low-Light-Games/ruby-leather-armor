# frozen_string_literal: true

module DungeonMasterLight
  # Processes actions declared by the AI narrative response.
  # Creates models, starts encounters, moves the party -- all in-app, no AI.
  class ActionResolver
    attr_reader :combat_started

    def initialize(adventure, log:)
      @adventure = adventure
      @log = log
      @combat_started = false
    end

    # @param actions [Array<Hash>] actions from the AI response
    # @return [Array<String>] log messages for what happened
    def resolve(actions)
      return [] if actions.blank?

      results = []

      actions.each do |action|
        case action["type"]
        when "start_combat"
          results << resolve_start_combat(action)
        when "create_npc"
          results << resolve_create_npc(action)
        when "create_location"
          results << resolve_create_location(action)
        when "move_party"
          results << resolve_move_party(action)
        when "update_attitude"
          results << resolve_update_attitude(action)
        else
          @log.dm_log!("Unknown action type: #{action['type']}")
        end
      end

      results.compact
    end

    private

    def resolve_start_combat(action)
      enemies = action["enemies"] || []
      return "start_combat: no enemies specified" if enemies.empty?

      return "start_combat: combat already active" if @adventure.active_encounter

      creature_sheets = enemies.map do |enemy_data|
        CreatureSheet.find_or_create_by!(
          adventure: @adventure,
          name: enemy_data["name"]
        ) do |cs|
          cs.creature_type = enemy_data["creature_type"] || "monster"
          cs.level = enemy_data["level"] || 1
          cs.race = enemy_data["race"]
          cs.character_class = enemy_data["class"]
          cs.attitude = "hostile"
          cs.strength = enemy_data["strength"] || 10
          cs.dexterity = enemy_data["dexterity"] || 10
          cs.constitution = enemy_data["constitution"] || 10
          cs.intelligence = enemy_data["intelligence"] || 10
          cs.wisdom = enemy_data["wisdom"] || 10
          cs.charisma = enemy_data["charisma"] || 10
        end
      end

      creature_sheets.each { |cs| cs.recompute_derived_stats! if cs.derived_stats.blank? }

      combat_service = DungeonMasterLight::CombatService.new(@adventure, log: @log)
      combat_service.start_encounter(creature_sheets)

      @combat_started = true
      @log.dm_log!("Combat initiated with: #{creature_sheets.map(&:name).join(', ')}")
      "combat_started"
    rescue => e
      @log.dm_log!("Failed to start combat: #{e.message}")
      nil
    end

    def resolve_create_npc(action)
      name = action["name"]
      return nil if name.blank?

      cs = CreatureSheet.find_or_create_by!(
        adventure: @adventure,
        name: name
      ) do |npc|
        npc.creature_type = action["creature_type"] || "npc"
        npc.attitude = action["attitude"] || "indifferent"
        npc.details = action["details"] || {}
        npc.level = action["level"] || 1
        npc.race = action["race"] || "human"
        npc.character_class = action["class"]
      end

      @log.dm_log!("NPC created/found: #{cs.name} (#{cs.attitude})")
      "npc_created:#{cs.name}"
    rescue => e
      @log.dm_log!("Failed to create NPC '#{name}': #{e.message}")
      nil
    end

    def resolve_create_location(action)
      name = action["name"]
      return nil if name.blank?

      location = Location.find_or_create_by!(
        adventure: @adventure,
        name: name
      ) do |loc|
        loc.terrain_type = action["terrain"] || "road"
        loc.description = action["description"]
      end

      if action["distance_from_current"].present?
        current = @adventure.current_location
        if current && current != location
          LocationEdge.find_or_create_by!(
            from_location: current,
            to_location: location
          ) do |edge|
            edge.distance_miles = action["distance_from_current"]
            edge.terrain_type = action["terrain"] || "road"
          end
        end
      end

      @log.dm_log!("Location created/found: #{location.name} (#{location.terrain_type})")
      "location_created:#{location.name}"
    rescue => e
      @log.dm_log!("Failed to create location '#{name}': #{e.message}")
      nil
    end

    def resolve_move_party(action)
      destination_name = action["to"]
      return nil if destination_name.blank?

      destination = @adventure.locations.find_by(name: destination_name)
      unless destination
        destination = Location.create!(
          adventure: @adventure,
          name: destination_name,
          terrain_type: "road"
        )
      end

      @adventure.locations.where(is_current: true).update_all(is_current: false)
      destination.update!(is_current: true)

      @log.dm_log!("Party moved to: #{destination.name}")
      "party_moved:#{destination.name}"
    rescue => e
      @log.dm_log!("Failed to move party to '#{destination_name}': #{e.message}")
      nil
    end

    def resolve_update_attitude(action)
      name = action["name"]
      return nil if name.blank?

      npc = @adventure.creature_sheets.find_by(name: name)
      return nil unless npc

      direction = action["direction"] == "worse" ? :worse : :better
      npc.shift_attitude!(direction)

      @log.dm_log!("NPC #{name} attitude shifted #{direction} to #{npc.attitude}")
      "attitude_updated:#{name}:#{npc.attitude}"
    rescue => e
      @log.dm_log!("Failed to update attitude for '#{name}': #{e.message}")
      nil
    end
  end
end
