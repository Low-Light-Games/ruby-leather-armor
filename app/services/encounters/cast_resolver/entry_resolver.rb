# frozen_string_literal: true

module Encounters
  class CastResolver
    class EntryResolver
      TYPE_ENUM        = %w[beast fighter goblinoid spellcaster commoner].freeze
      DEFAULT_TYPE     = "fighter"
      DEFAULT_ATTITUDE = "indifferent"

      def initialize(adventure:, ai:, log:)
        @adventure = adventure
        @ai        = ai
        @log       = log
      end

      # @param entry [Hash] one AI-emitted entry, e.g. `{ "name" => "...", "type" => "...", "count" => 5 }`
      # @return [Array<AdventureNpc>]
      def resolve(entry)
        name  = entry["name"].to_s.strip
        type  = clamp_type(entry["type"])
        count = clamp_count(entry["count"])
        return [] if name.empty?

        if count == 1
          reused_or_adopted = reuse_or_adopt_existing(name)
          return [reused_or_adopted] if reused_or_adopted
        end

        cold_spawn_from_bestiary(name: name, type: type, count: count)
      end

      private

      def clamp_type(raw)
        type = raw.to_s.downcase.strip
        TYPE_ENUM.include?(type) ? type : DEFAULT_TYPE
      end

      def clamp_count(raw)
        n = Integer(raw) rescue 1
        n.clamp(1, Encounters::ActorSheetCreation::MAX_COUNT)
      end

      def reuse_or_adopt_existing(name)
        existing_npc = lookup_adventure_npc_by_name(name)
        return existing_npc if existing_npc&.actor_sheet_id

        sheet = lookup_adventure_actor_sheet_by_name(name)
        return nil unless sheet

        if existing_npc
          existing_npc.update!(actor_sheet_id: sheet.id) if existing_npc.actor_sheet_id.nil?
          existing_npc
        else
          insert_runtime_npcs([sheet], display_name_override: name).first
        end
      end

      def cold_spawn_from_bestiary(name:, type:, count:)
        bestiary = bestiary_by_name(name) || bestiary_by_default_for_type(type)
        unless bestiary
          report_unresolved!(name: name, type: type, count: count)
          return []
        end

        log_default_fallback!(name: name, type: type, count: count, bestiary: bestiary) if bestiary.default_for_type

        sheets = Encounters::ActorSheetCreation.from_bestiary(
          adventure:      @adventure,
          bestiary_entry: bestiary,
          display_name:   name,
          count:          count,
        )
        insert_runtime_npcs(sheets)
      end

      def lookup_adventure_npc_by_name(name)
        AdventureNpc
          .for_adventure(@adventure)
          .where("LOWER(name) = ?", name.downcase)
          .first
      end

      def lookup_adventure_actor_sheet_by_name(name)
        @adventure.adventure_actor_sheets.where("LOWER(name) = ?", name.downcase).first
      end

      def bestiary_by_name(name)
        BestiaryEntry
          .where(story_id: [@adventure.story_id, nil])
          .find_by("LOWER(name) = ?", name.downcase)
      end

      def bestiary_by_default_for_type(type)
        BestiaryEntry.default_for(type).first
      end

      def insert_runtime_npcs(sheets, display_name_override: nil)
        records = sheets.map do |sheet|
          Lore::NpcRecord.new(
            name:           display_name_override || sheet.name,
            attitude:       DEFAULT_ATTITUDE,
            actor_sheet_id: sheet.id,
          )
        end
        Lore::ApplyNpcs.call(
          adventure:   @adventure,
          log:         @log,
          ai:          @ai,
          npc_records: records,
          source:      "runtime",
        )
      end

      def report_unresolved!(name:, type:, count:)
        @log.play_log!(
          "cast_resolver_unresolved",
          "CastResolver: no bestiary entry for name=#{name.inspect} type=#{type.inspect}",
          parsed_response: CastResolverEvents::Unresolved.new(
            name: name, type: type, count: count, adventure_id: @adventure.id,
          ).to_h,
        )
        ApplicationErrorReporter.notify(
          RuntimeError.new("CastResolver default lookup miss for type=#{type.inspect}"),
          context: error_context.with(source: "cast_resolver_unresolved", name: name, type: type),
        )
      end

      def log_default_fallback!(name:, type:, count:, bestiary:)
        @log.play_log!(
          "cast_resolver_default_fallback",
          "CastResolver: default_for_type=#{type} for name=#{name.inspect}",
          parsed_response: CastResolverEvents::DefaultFallback.new(
            name: name, type: type, count: count, bestiary_entry_id: bestiary.id,
          ).to_h,
        )
      end

      def error_context
        Lore::ErrorContext.new(
          step:         "cast_resolver",
          adventure_id: @adventure.id,
          loop_id:      nil,
          source:       "cast_resolver",
        )
      end
    end
  end
end
