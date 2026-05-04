# frozen_string_literal: true

module Adventures
  class Bootstrap
    # @param story   [Story]
    # @param sheet   [Sheet]
    # @param user    [User]
    # @param options [Hash]
    #   :directed_dm [Boolean] default false
    #   :skip_world_sanity_check [Boolean] default false
    def initialize(story:, sheet:, user:, **options)
      @story    = story
      @sheet    = sheet
      @user     = user
      @directed_dm             = options.fetch(:directed_dm, false)
      @skip_world_sanity_check = options.fetch(:skip_world_sanity_check, false)
    end

    # @return [Adventure]
    def call
      adventure = build_adventure!
      ensure_opening_message(adventure)
      run_narrative_facts_seed(adventure)
      adventure.reload
    end

    private

    def build_adventure!
      stats     = StartingStats.new(@sheet)
      start_loc = @story.starting_location

      adventure = Adventure.create!(
        user:                    @user,
        story:                   @story,
        dm_mode:                 "standard",
        directed_dm:             @directed_dm,
        skip_world_sanity_check: @skip_world_sanity_check,
        current_location:        start_loc,
      )

      SheetCopier.new(adventure, @sheet,
        max_hp:   stats.starting_hp,
        currency: stats.remaining_currency
      ).call

      adventure
    end

    def ensure_opening_message(adventure)
      return if adventure.adventure_messages.exists?

      content = @story.opening_message.presence
      return if content.blank?

      adventure.adventure_messages.create!(
        role:         "dm",
        content:      content,
        message_type: "narrative",
      )
    end

    # SeedFromAdventure is lossy-with-Sentry internally; this rescue
    # guarantees adventure creation never fails because seeding did.
    def run_narrative_facts_seed(adventure)
      DungeonMaster::Lore::SeedFromAdventure.call(adventure: adventure, user: @user)
    rescue StandardError => e
      ApplicationErrorReporter.notify(
        e, context: { source: "adventures_bootstrap_narrative_facts_seed", adventure_id: adventure.id }
      )
      Rails.logger.error("[Adventures::Bootstrap] Narrative facts seed failed: #{e.message}")
    end
  end
end
