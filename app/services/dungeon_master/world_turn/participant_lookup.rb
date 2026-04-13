# frozen_string_literal: true

module DungeonMaster
  module WorldTurn
    # AC / creature_sheet_id from combat_context participant rows + live sheets.
    module ParticipantLookup
      module_function

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
    end
  end
end
