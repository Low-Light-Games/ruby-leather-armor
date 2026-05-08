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
      bind_starting_adventure_location!(adventure)
      adventure.reload
    end

    private

    def build_adventure!
      stats = StartingStats.new(@sheet)

      adventure = Adventure.create!(
        user:                    @user,
        story:                   @story,
        dm_mode:                 "standard",
        directed_dm:             @directed_dm,
        skip_world_sanity_check: @skip_world_sanity_check,
      )

      SheetCopier.new(adventure, @sheet,
        max_hp:   stats.starting_hp,
        currency: stats.remaining_currency
      ).call

      adventure
    end

    def bind_starting_adventure_location!(adventure)
      starting_story_location = @story.starting_location
      return unless starting_story_location

      starting_adventure_location = AdventureLocation.where(
        adventure_id:      adventure.id,
        story_location_id: starting_story_location.id,
      ).first
      return unless starting_adventure_location

      adventure.update!(current_location_id: starting_adventure_location.id)
    end

    def ensure_opening_message(adventure)
      return if adventure.adventure_messages.exists?

      jit_generate_opening_message_if_blank!

      adventure.adventure_messages.create!(
        role:         "dm",
        content:      @story.opening_message,
        message_type: "narrative",
      )
    end

    # Self-healing path for stories created before opening_message was
    # required: generate one from the premise, persist it back to the
    # story, then proceed. Subsequent adventures from the same story
    # reuse the persisted value at no AI cost.
    def jit_generate_opening_message_if_blank!
      return if @story.opening_message.present?

      Lore::GenerateOpeningMessage.call(story: @story, user: @user)
      @story.reload
    end

    # SeedFromAdventure is lossy-with-Sentry internally; this rescue
    # guarantees adventure creation never fails because seeding did.
    def run_narrative_facts_seed(adventure)
      Lore::SeedFromAdventure.call(adventure: adventure, user: @user)
    rescue StandardError => e
      ApplicationErrorReporter.notify(
        e, context: { source: "adventures_bootstrap_narrative_facts_seed", adventure_id: adventure.id }
      )
      Rails.logger.error("[Adventures::Bootstrap] Narrative facts seed failed: #{e.message}")
    end
  end
end
