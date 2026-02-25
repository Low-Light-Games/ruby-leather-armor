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
                   .includes(adventure_sheets: [], story_state: :story)
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
    sheet = current_user.sheets.find(params[:sheet_id])
    initial_state = story.story_states.kept.order(:position).first

    unless initial_state
      return render json: { error: "This story has no states yet" }, status: :unprocessable_entity
    end

    max_hp = compute_starting_hp(sheet)

    @adventure = Adventure.new(
      user: current_user,
      story_state: initial_state
    )

    if @adventure.save
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
        gold: 0,
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

      adv_sheet.recompute_derived_stats!
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

  def adventure_summary(adventure)
    adv_sheet = adventure.adventure_sheets.first
    {
      id: adventure.id,
      character_name: adv_sheet&.name || "Unknown",
      story_title: adventure.story_state.story.title,
      character_gold: adv_sheet&.gold || 0,
      created_at: adventure.created_at,
      updated_at: adventure.updated_at
    }
  end

  def adventure_json(adventure)
    adv_sheet = adventure.adventure_sheets
                         .includes(:adventure_sheet_feats, :adventure_sheet_spells)
                         .first
    {
      id: adventure.id,
      adventure_sheet: adventure_sheet_json(adv_sheet),
      story_state: adventure.story_state,
      story: adventure.story_state.story
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

    # Merge into details for backward compatibility with frontend
    details = (base["details"] || {}).dup
    details["feats"] = feats
    details["knownSpells"] = known_spells
    details["spellbook"] = spellbook_spells
    base["details"] = details

    base
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
