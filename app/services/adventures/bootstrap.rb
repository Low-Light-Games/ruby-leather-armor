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
  end
end
