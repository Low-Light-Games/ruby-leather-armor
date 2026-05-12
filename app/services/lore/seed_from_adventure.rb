# frozen_string_literal: true

module Lore
  class SeedFromAdventure
    def self.call(adventure:, user: nil, ai: nil, log: nil, config: nil)
      new(adventure: adventure, user: user, ai: ai, log: log, config: config).call
    end

    def initialize(adventure:, user: nil, ai: nil, log: nil, config: nil)
      @adventure = adventure
      @user      = user || adventure.user
      @config    = config || DmConfig.instance
      @ai        = ai || Ai::Client.new(@config)
      @log       = log || Ai::Logging.new(
        adventure: @adventure, user: @user, dm_service: "standard"
      )
    end

    def call
      seed_npcs!
      seed_locations!
      seed_facts_from_story!
    rescue StandardError => e
      handle_seed_failure(e)
      FactsChangeSet.empty
    end

    private

    def seed_facts_from_story!
      facts = Array(@adventure.story&.seed_facts)
      return FactsChangeSet.empty if facts.empty?

      ApplyResults.call(
        adventure: @adventure,
        loop:      nil,
        log:       @log,
        ai:        @ai,
        result:    { "facts" => facts },
        source:    "seed",
      )
    end

    def handle_seed_failure(exception)
      @log.report_error(exception, context: {
        step: "lore_seed",
        adventure_id: @adventure&.id,
        source: "seed_from_adventure",
      })
      @log.play_log!(
        "seed_failure",
        "Lore seed failed: #{exception.class}",
        parsed_response: { error: exception.message.to_s.truncate(500) },
      )
    end

    def seed_npcs!
      story_npcs = StoryNpc.for_adventure(@adventure).ordered_by_id.to_a
      return if story_npcs.empty?

      records = story_npcs.map do |npc|
        NpcRecord.from_story_npc(npc, actor_sheet_id: clone_sheet_for(npc))
      end

      ApplyNpcs.call(
        adventure:   @adventure,
        log:         @log,
        ai:          @ai,
        npc_records: records,
        source:      "seed",
      )
    rescue StandardError => e
      @log.report_error(e, context: {
        step:         "apply_npcs_seed",
        adventure_id: @adventure&.id,
        source:       "seed_from_adventure",
      })
      @log.play_log!(
        "npc_seed_failure",
        "ApplyNpcs seed failed: #{e.class}",
        parsed_response: { error: e.message.to_s.truncate(500) },
      )
    end

    # @return [Integer, nil]
    def clone_sheet_for(story_npc)
      bestiary_entry = story_npc.bestiary_entry
      return nil unless bestiary_entry

      sheet = Encounters::ActorSheetCreation.from_bestiary(
        adventure:      @adventure,
        bestiary_entry: bestiary_entry,
        display_name:   story_npc.name,
      ).first
      sheet&.id
    rescue StandardError => e
      @log.report_error(e, context: {
        step:         "seed_clone_adventure_actor_sheet",
        adventure_id: @adventure&.id,
        story_npc_id: story_npc.id,
        source:       "seed_from_adventure",
      })
      nil
    end

    def seed_locations!
      story_locations = @adventure.story.story_locations.order(:id).to_a
      return if story_locations.empty?

      coordinates = Maps::PlaceLocations.call(
        count: story_locations.size,
        seed:  @adventure.story_id,
      )
      records = story_locations.zip(coordinates).map do |location, (x, y)|
        LocationRecord.from_story_location(location, x: x, y: y)
      end

      ApplyLocations.call(
        adventure:        @adventure,
        log:              @log,
        ai:               @ai,
        location_records: records,
        source:           "seed",
      )
    rescue StandardError => e
      @log.report_error(e, context: {
        step:         "apply_locations_seed",
        adventure_id: @adventure&.id,
        source:       "seed_from_adventure",
      })
      @log.play_log!(
        "location_seed_failure",
        "ApplyLocations seed failed: #{e.class}",
        parsed_response: { error: e.message.to_s.truncate(500) },
      )
    end
  end
end
