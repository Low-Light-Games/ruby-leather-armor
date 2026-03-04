# frozen_string_literal: true

class AdventuresController < ApplicationController
  skip_before_action :require_login, only: [:new]
  before_action :set_adventure, only: [:show, :destroy]

  # GET /adventures/new - serves the SPA page for creating an adventure
  def new
    render layout: "application"
  end

  # GET /adventures - returns the current user's ongoing adventures as JSON
  def index
    adventures = policy_scope(Adventure)
                   .includes(adventure_sheets: [], story: [])
                   .order(updated_at: :desc)

    render json: adventures.map { |a| adventure_summary(a) }
  end

  # GET /adventures/:id - serves the SPA page OR returns JSON for the API
  def show
    authorize(@adventure)

    respond_to do |format|
      format.html { render layout: "application" }
      format.json do
        render json: adventure_json(@adventure)
      end
    end
  end

  # POST /adventures - API endpoint to create an adventure
  def create
    story = Story.kept.find(params[:story_id])
    sheet = policy_scope(Sheet).find(params[:sheet_id])

    max_hp = compute_starting_hp(sheet)

    directed_dm = ActiveModel::Type::Boolean.new.cast(params[:directed_dm]) && FeatureFlag.enabled?(:directed_dm)

    start_loc = story.starting_location

    @adventure = Adventure.new(
      user: current_user,
      story: story,
      dm_mode: "standard",
      directed_dm: directed_dm,
      current_location: start_loc,
      traversal_context: build_initial_traversal(start_loc),
      combat_context: {},
      social_context: {},
      time_context: build_initial_time_context(story),
      story_summary: story.initial_summary
    )

    if @adventure.save
      opening_text = story.initial_context.presence || story.preview
      @adventure.adventure_messages.create!(
        role: "dm",
        content: opening_text,
        message_type: "narrative"
      )

      # Create adventure sheet — a full copy of the character for this adventure
      adv_sheet = @adventure.adventure_sheets.create!(
        sheet: sheet,
        name: sheet.name,
        description: sheet.description,
        strength: sheet.strength,
        intelligence: sheet.intelligence,
        dexterity: sheet.dexterity,
        constitution: sheet.constitution,
        wisdom: sheet.wisdom,
        charisma: sheet.charisma,
        race: sheet.race,
        racial_bonus_attribute: sheet.racial_bonus_attribute,
        character_class: sheet.character_class,
        subclass: sheet.subclass,
        level: sheet.level,
        details: (sheet.details || {}).deep_dup,
        currency: remaining_currency(sheet),
        hp: max_hp,
        max_hp: max_hp,
        items: nil,
        effects: nil
      )

      # Copy feat selections from the original sheet
      sheet.sheet_feats.each do |sf|
        adv_sheet.adventure_sheet_feats.create!(feat_id: sf.feat_id, choice: sf.choice)
      end

      # Copy spell selections from the original sheet
      sheet.sheet_spells.each do |ss|
        adv_sheet.adventure_sheet_spells.create!(spell_id: ss.spell_id, storage_type: ss.storage_type)
      end

      # Copy item selections from the original sheet
      sheet.sheet_items.each do |si|
        adv_sheet.adventure_sheet_items.create!(
          item_definition_id: si.item_definition_id,
          quantity: si.quantity,
          equipped: si.equipped,
          slot_override: si.slot_override
        )
      end

      adv_sheet.recompute_derived_stats!

      @adventure.update!(plot_state: {
        "discovered_clues" => [],
        "attempted_clues" => [],
        "reached_milestones" => [],
        "npc_met" => [],
        "npc_attitudes" => {},
        "custom_facts" => [],
      })

      run_embellisher(@adventure)

      @adventure.reload
      render json: adventure_json(@adventure), status: :created
    else
      render json: { errors: @adventure.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /adventures/:id
  def destroy
    authorize(@adventure)
    @adventure.destroy!
    render json: { message: "Adventure deleted" }, status: :ok
  end

  private

  def set_adventure
    @adventure = Adventure.find(params[:id])
  end

  TIME_CUE_PATTERNS = {
    /\b(\d{1,2})\s*(?:in the\s+)?(?:am|a\.m\.|in the morning)\b/i => ->(m) { m[1].to_i },
    /\b(\d{1,2})\s*(?:pm|p\.m\.|in the (?:afternoon|evening))\b/i => ->(m) { m[1].to_i + 12 },
    /\bmidnight\b/i      => ->(_) { 0 },
    /\bnoon\b/i          => ->(_) { 12 },
    /\bmidday\b/i        => ->(_) { 12 },
    /\bdawn\b/i          => ->(_) { 6 },
    /\bsunrise\b/i       => ->(_) { 6 },
    /\bdusk\b/i          => ->(_) { 19 },
    /\bsunset\b/i        => ->(_) { 19 },
    /\bmorning\b/i       => ->(_) { 8 },
    /\bafternoon\b/i     => ->(_) { 14 },
    /\bevening\b/i       => ->(_) { 19 },
    /\bnight\b/i         => ->(_) { 21 },
  }.freeze

  def build_initial_time_context(story)
    hour = parse_time_cue(story.initial_context) ||
           parse_time_cue(story.hook) ||
           8
    hour = hour.clamp(0, 23)

    {
      "current_hour" => hour,
      "adventure_day" => 1,
      "light_conditions" => DungeonMaster::Utilities::GameClock.light_for_hour(hour),
      "hours_since_last_rest" => 0,
      "hours_since_last_encounter_check" => 0
    }
  end

  def parse_time_cue(text)
    return nil if text.blank?

    TIME_CUE_PATTERNS.each do |pattern, extractor|
      match = text.match(pattern)
      return extractor.call(match) if match
    end
    nil
  end

  def build_initial_traversal(start_loc)
    return {} unless start_loc

    ctx = {
      "current_location" => start_loc.name,
      "scene" => start_loc.description,
    }

    exits = start_loc.neighbors.pluck(:name)
    ctx["exits"] = exits if exits.any?

    ctx
  end

  def adventure_summary(adventure)
    adv_sheet = adventure.adventure_sheets.first
    {
      id: adventure.id,
      character_name: adv_sheet&.name || "Unknown",
      story_title: adventure.story.title,
      character_currency: adv_sheet&.currency || { "gold" => 0, "silver" => 0, "copper" => 0, "platinum" => 0 },
      created_at: adventure.created_at,
      updated_at: adventure.updated_at
    }
  end

  def adventure_json(adventure)
    adv_sheet = adventure.adventure_sheets
                         .includes(:adventure_sheet_feats, :adventure_sheet_spells, :adventure_sheet_items)
                         .first
    {
      id: adventure.id,
      adventure_sheet: adventure_sheet_json(adv_sheet),
      story: adventure.story,
      traversal_context: adventure.traversal_context,
      combat_context: adventure.combat_context,
      social_context: adventure.social_context,
      exploration_context: adventure.exploration_context,
      rest_context: adventure.rest_context,
      inventory_context: adventure.inventory_context,
      time_context: adventure.time_context,
      story_summary: adventure.story_summary,
      scene_summary: adventure.scene_summary,
      current_category: adventure.current_category,
      directed_dm: adventure.directed_dm?
    }
  end

  def adventure_sheet_json(adv_sheet)
    return nil unless adv_sheet

    base = adv_sheet.as_json

    feats = adv_sheet.adventure_sheet_feats.map { |sf|
      sf.choice ? "#{sf.feat_id}::#{sf.choice}" : sf.feat_id
    }

    known_spells = adv_sheet.adventure_sheet_spells.where(storage_type: "known").pluck(:spell_id)
    spellbook_spells = adv_sheet.adventure_sheet_spells.where(storage_type: "spellbook").pluck(:spell_id)

    items = adv_sheet.adventure_sheet_items.includes(:item_definition).map { |si|
      {
        itemId: si.item_definition_id,
        quantity: si.quantity,
        equipped: si.equipped,
        slotOverride: si.slot_override,
      }
    }

    # Merge into details for backward compatibility with frontend
    details = (base["details"] || {}).dup
    details["feats"] = feats
    details["knownSpells"] = known_spells
    details["spellbook"] = spellbook_spells
    details["items"] = items
    base["details"] = details

    base
  end

  def run_embellisher(adventure)
    DungeonMaster::Embellisher.new(adventure).run
  rescue DungeonMaster::AiError, DungeonMaster::TokenBudgetExceededError => e
    Rails.logger.error("[AdventuresController] Embellisher failed: #{e.message}")
  end

  # Compute remaining currency after item purchases.
  # Works in copper pieces to avoid floating-point drift.
  def remaining_currency(sheet)
    currency = (sheet.currency || {}).deep_dup
    total_cp = (currency["platinum"].to_i * 1000) +
               (currency["gold"].to_i * 100) +
               (currency["silver"].to_i * 10) +
               currency["copper"].to_i

    items_cost_cp = sheet.sheet_items.includes(:item_definition).sum do |si|
      cost_gp = si.item_definition&.cost_gp || 0
      (cost_gp * 100 * si.quantity).round
    end

    remaining_cp = [total_cp - items_cost_cp, 0].max

    pp, remaining_cp = remaining_cp.divmod(1000)
    gp, remaining_cp = remaining_cp.divmod(100)
    sp, cp = remaining_cp.divmod(10)

    { "platinum" => pp, "gold" => gp, "silver" => sp, "copper" => cp }
  end

  # Compute starting HP: max hit die + CON modifier at level 1,
  # then (hit_die/2 + 1 + CON mod) per additional level.
  def compute_starting_hp(sheet)
    hit_die_map = {
      "barbarian" => 12, "bard" => 8, "cleric" => 8, "druid" => 8,
      "fighter" => 10, "monk" => 8, "paladin" => 10, "ranger" => 10,
      "rogue" => 8, "sorcerer" => 6, "wizard" => 6
    }

    race_con_mod = {
      "dwarf" => 2, "elf" => -2, "gnome" => 2,
      "halfling" => 0, "human" => 0, "half_elf" => 0, "half_orc" => 0
    }

    hit_die = hit_die_map[sheet.character_class] || 8
    racial_con = race_con_mod[sheet.race] || 0
    flexible_con = sheet.racial_bonus_attribute == "constitution" ? 2 : 0
    final_con = sheet.constitution + racial_con + flexible_con
    con_modifier = ((final_con - 10).to_f / 2).floor

    level_1_hp = [hit_die + con_modifier, 1].max

    additional_per_level = [(hit_die / 2) + 1 + con_modifier, 1].max
    total_hp = level_1_hp + (sheet.level - 1) * additional_per_level

    [total_hp, 1].max
  end
end
