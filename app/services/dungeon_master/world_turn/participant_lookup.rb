# frozen_string_literal: true

module DungeonMaster
  module WorldTurn
    # AC / creature_sheet_id from combat_context participant rows + live sheets.
    module ParticipantLookup
      module_function

      DEFENSE_KIND_TO_STAT = {
        "full_ac" => "ac",
        "touch_ac" => "touch_ac",
        "flat_footed_ac" => "flat_footed_ac"
      }.freeze

      def creature_sheet_id_for_name(name, combat_ctx)
        p = Array(combat_ctx["participants"]).find { |x| x["name"].to_s == name.to_s }
        sid = p && p["creature_sheet_id"]
        sid.present? ? sid.to_i : nil
      end

      def ac_for_name(name, combat_ctx:, player_sheet:, adventure:)
        return player_sheet.derived_stats.fetch("ac").to_i if name.to_s.casecmp("player").zero?

        sid = creature_sheet_id_for_name(name, combat_ctx)
        return nil unless sid

        c = adventure.creature_sheets.find_by(id: sid)
        (c&.derived_stats || {})["ac"]&.to_i
      end

      # Strict combat targeting: participant names only (case-insensitive exact). "player" → PC sheet.
      # @return [Array<Symbol, AdventureSheet|CreatureSheet>] `[:player, sheet]` or `[:creature, sheet]`
      def resolve_target_sheet!(target_name, combat_ctx:, player_sheet:, adventure:)
        n = target_name.to_s.strip
        if n.casecmp("player").zero?
          raise DungeonMaster::CombatMechanicResolutionError, "player sheet required" if player_sheet.nil?

          return [:player, player_sheet]
        end

        participants = Array(combat_ctx["participants"])
        matches = participants.select { |p| p["name"].to_s.strip.casecmp(n).zero? }
        if matches.empty?
          raise DungeonMaster::CombatMechanicResolutionError.new(
            "target not in combat participants: #{target_name.inspect}",
            code: :target_not_found
          )
        end
        if matches.size > 1
          raise DungeonMaster::CombatMechanicResolutionError.new(
            "ambiguous combat target: #{target_name.inspect}",
            code: :ambiguous_target
          )
        end

        sid = matches.first["creature_sheet_id"].to_i
        creature = adventure.creature_sheets.find_by(id: sid)
        unless creature
          raise DungeonMaster::CombatMechanicResolutionError.new(
            "creature sheet missing for participant (id=#{sid})",
            code: :creature_missing
          )
        end

        [:creature, creature]
      end

      # @param defense_kind [String] full_ac | touch_ac | flat_footed_ac
      def defense_dc_for_target!(target_name, defense_kind, combat_ctx:, player_sheet:, adventure:)
        stat_key = DEFENSE_KIND_TO_STAT[defense_kind.to_s]
        unless stat_key
          raise DungeonMaster::CombatMechanicResolutionError.new(
            "invalid defense_kind: #{defense_kind.inspect}",
            code: :invalid_defense_kind
          )
        end

        _kind, sheet = resolve_target_sheet!(target_name, combat_ctx:, player_sheet:, adventure:)
        ds = sheet.derived_stats || {}
        val = ds[stat_key] || ds[stat_key.to_sym]
        if val.nil?
          raise DungeonMaster::CombatMechanicResolutionError.new(
            "missing #{stat_key} on target sheet",
            code: :missing_derived_stat
          )
        end

        val.to_i
      end
    end
  end
end
