# frozen_string_literal: true

module DungeonMasterLight
  # Resolves data requests declared by the AI narrative response.
  # Queries ActiveRecord models and returns structured data.
  class DataResolver
    def initialize(adventure)
      @adventure = adventure
    end

    # @param data_requests [Array<Hash>] data requests from AI response
    # @return [Hash] resolved data keyed by request description
    def resolve(data_requests)
      return {} if data_requests.blank?

      results = {}

      data_requests.each do |request|
        key = request_key(request)
        results[key] = case request["type"]
                        when "npc_attitude"
                          resolve_npc_attitude(request["name"])
                        when "npc_sheet"
                          resolve_npc_sheet(request["name"])
                        when "distance"
                          resolve_distance(request["from"], request["to"])
                        when "current_location"
                          resolve_current_location
                        when "party_status"
                          resolve_party_status
                        else
                          { error: "unknown request type: #{request['type']}" }
                        end
      end

      results
    end

    private

    def request_key(request)
      case request["type"]
      when "npc_attitude" then "attitude:#{request['name']}"
      when "npc_sheet" then "sheet:#{request['name']}"
      when "distance" then "distance:#{request['from']}->#{request['to']}"
      when "current_location" then "current_location"
      when "party_status" then "party_status"
      else "unknown:#{request['type']}"
      end
    end

    def resolve_npc_attitude(name)
      npc = @adventure.creature_sheets.find_by(name: name)
      return { error: "NPC '#{name}' not found" } unless npc

      { name: npc.name, attitude: npc.attitude, creature_type: npc.creature_type }
    end

    def resolve_npc_sheet(name)
      npc = @adventure.creature_sheets
              .includes(:creature_sheet_feats, :creature_sheet_items, :creature_sheet_spells)
              .find_by(name: name)
      return { error: "NPC '#{name}' not found" } unless npc

      {
        name: npc.name,
        creature_type: npc.creature_type,
        attitude: npc.attitude,
        level: npc.level,
        race: npc.race,
        character_class: npc.character_class,
        hp: npc.hp,
        max_hp: npc.max_hp,
        details: npc.details
      }
    end

    def resolve_distance(from_name, to_name)
      from_loc = @adventure.locations.find_by(name: from_name)
      to_loc = @adventure.locations.find_by(name: to_name)

      return { error: "Location '#{from_name}' not found" } unless from_loc
      return { error: "Location '#{to_name}' not found" } unless to_loc

      distance = from_loc.distance_to(to_loc)
      return { error: "No known distance between '#{from_name}' and '#{to_name}'" } unless distance

      { from: from_name, to: to_name, distance_miles: distance.to_f }
    end

    def resolve_current_location
      location = @adventure.current_location
      return { error: "Party has no current location" } unless location

      { name: location.name, terrain_type: location.terrain_type, description: location.description }
    end

    def resolve_party_status
      sheet = @adventure.adventure_sheets.first
      return { error: "No player character found" } unless sheet

      ds = sheet.derived_stats || {}
      {
        name: sheet.name,
        hp: sheet.hp,
        max_hp: sheet.max_hp,
        ac: ds["ac"],
        level: sheet.level,
        race: sheet.race,
        character_class: sheet.character_class
      }
    end
  end
end
