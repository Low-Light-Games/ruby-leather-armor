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
      LookupContext = Struct.new(:combat_ctx, :player_sheet, :adventure, keyword_init: true)

      def creature_sheet_id_for_name(name, combat_ctx)
        participant = Array(combat_ctx["participants"]).find { |entry| entry["name"].to_s == name.to_s }
        creature_sheet_id = participant && participant["creature_sheet_id"]
        creature_sheet_id.present? ? creature_sheet_id.to_i : nil
      end

      def ac_for_name(name, context: nil, **kwargs)
        lookup = context || LookupContext.new(**kwargs)
        return lookup.player_sheet.derived_stats.fetch("ac").to_i if name.to_s.casecmp("player").zero?

        creature_sheet_id = creature_sheet_id_for_name(name, lookup.combat_ctx)
        return nil unless creature_sheet_id

        creature_sheet = lookup.adventure.creature_sheets.find_by(id: creature_sheet_id)
        (creature_sheet&.derived_stats || {})["ac"]&.to_i
      end

      # Strict combat targeting: participant names only (case-insensitive exact). "player" → PC sheet.
      # @return [Array<Symbol, AdventureSheet|CreatureSheet>] `[:player, sheet]` or `[:creature, sheet]`
      def resolve_target_sheet!(target_name, context: nil, **kwargs)
        lookup = context || LookupContext.new(**kwargs)
        normalized_target_name = target_name.to_s.strip
        if normalized_target_name.casecmp("player").zero?
          raise DungeonMaster::CombatMechanicResolutionError, "player sheet required" if lookup.player_sheet.nil?

          return [:player, lookup.player_sheet]
        end

        participants = Array(lookup.combat_ctx["participants"])
        matches = participants.select { |participant| participant["name"].to_s.strip.casecmp(normalized_target_name).zero? }
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

        creature_sheet_id = matches.first["creature_sheet_id"].to_i
        creature = lookup.adventure.creature_sheets.find_by(id: creature_sheet_id)
        unless creature
          raise DungeonMaster::CombatMechanicResolutionError.new(
            "creature sheet missing for participant (id=#{creature_sheet_id})",
            code: :creature_missing
          )
        end

        [:creature, creature]
      end

      def target_sheet!(target_name, context: nil, **kwargs)
        lookup = context || LookupContext.new(**kwargs)
        _target_kind, target_sheet = resolve_target_sheet!(target_name, context: lookup)
        target_sheet
      end

      # @param defense_kind [String] full_ac | touch_ac | flat_footed_ac
      def defense_dc_for_target!(target_name, defense_kind, context: nil, **kwargs)
        lookup = context || LookupContext.new(**kwargs)
        stat_key = DEFENSE_KIND_TO_STAT[defense_kind.to_s]
        unless stat_key
          raise DungeonMaster::CombatMechanicResolutionError.new(
            "invalid defense_kind: #{defense_kind.inspect}",
            code: :invalid_defense_kind
          )
        end

        sheet = target_sheet!(target_name, context: lookup)
        derived_stats = sheet.derived_stats || {}
        defense_dc = derived_stats[stat_key] || derived_stats[stat_key.to_sym]
        if defense_dc.nil?
          raise DungeonMaster::CombatMechanicResolutionError.new(
            "missing #{stat_key} on target sheet",
            code: :missing_derived_stat
          )
        end

        defense_dc.to_i
      end
    end
  end
end
