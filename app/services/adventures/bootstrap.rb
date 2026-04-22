# frozen_string_literal: true

module Adventures
  # Encapsulates the full adventure initialization flow shared between
  # AdventuresController#create and OnboardingController#complete.
  #
  # Steps (in order):
  #   1. Build Adventure with seeded contexts from ContextInitializer
  #   2. SheetCopier — create AdventureSheet from the player Sheet
  #   3. Seed plot_state with empty tracking arrays
  #   4. Run Embellisher (non-fatal — logs and continues on AI errors)
  #   5. Ensure an opening DM message exists
  #   6. Run Lore::SeedFromAdventure to populate the narrative facts store
  #      (non-fatal — internal rescue + Sentry + seed_failure play_log)
  #
  # Returns the persisted (reloaded) Adventure on success.
  # Raises ActiveRecord::RecordInvalid or ActiveRecord::RecordNotSaved on failure.
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
      seed_plot_state!(adventure)
      run_embellisher(adventure)
      ensure_opening_message(adventure)
      run_narrative_facts_seed(adventure)
      adventure.reload
    end

    private

    def build_adventure!
      stats     = StartingStats.new(@sheet)
      ctx       = ContextInitializer.new(@story)
      start_loc = @story.starting_location
      seed      = @story.initial_contexts || {}

      adventure = Adventure.create!(
        user:                    @user,
        story:                   @story,
        dm_mode:                 "standard",
        directed_dm:             @directed_dm,
        skip_world_sanity_check: @skip_world_sanity_check,
        current_location:        start_loc,
        traversal_context:       (seed["traversal_context"] || {}).deep_merge(ctx.build_traversal(start_loc)),
        combat_context:          seed["combat_context"]     || {},
        social_context:          seed["social_context"]     || {},
        exploration_context:     seed["exploration_context"] || {},
        rest_context:            seed["rest_context"]       || {},
        inventory_context:       seed["inventory_context"]  || {},
        time_context:            ctx.build_time_context,
        story_summary:           @story.initial_summary,
      )

      SheetCopier.new(adventure, @sheet,
        max_hp:   stats.starting_hp,
        currency: stats.remaining_currency
      ).call

      adventure
    end

    def seed_plot_state!(adventure)
      adventure.update!(plot_state: {
        "discovered_clues"   => [],
        "attempted_clues"    => [],
        "reached_milestones" => [],
        "npc_met"            => [],
        "npc_attitudes"      => {},
        "custom_facts"       => [],
      })
    end

    def run_embellisher(adventure)
      DungeonMaster::Embellisher.new(adventure, user: @user).run
    rescue DungeonMaster::AiError, DungeonMaster::TokenBudgetExceededError => e
      ApplicationErrorReporter.notify(e, context: { source: "adventures_bootstrap_embellisher", adventure_id: adventure.id })
      Rails.logger.error("[Adventures::Bootstrap] Embellisher failed: #{e.message}")
    end

    def ensure_opening_message(adventure)
      return if adventure.adventure_messages.exists?

      adventure.adventure_messages.create!(
        role:         "dm",
        content:      @story.preview,
        message_type: "narrative"
      )
    end

    # Runs Loremaster in seed-call shape so turn 1's world check is not a
    # cold start. Placed *after* run_embellisher + ensure_opening_message
    # so enriched_world / the opening DM narrative / any Embellisher
    # Expand adventure-scoped NPCs and clues are all in place before the
    # seed call reads them (see plan §Concrete changes "Adventure
    # creation seeding" for input provenance).
    #
    # SeedFromAdventure is internally lossy-with-Sentry — it rescues its
    # own AI failures and emits a seed_failure play_log — so this call
    # site only needs a belt-and-braces top-level rescue in case the
    # service itself raises for a reason its own rescue doesn't cover.
    # Adventure creation must never fail because seeding failed: an
    # empty facts store degrades to the pre-plan world-check cold start,
    # not to a broken adventure.
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
