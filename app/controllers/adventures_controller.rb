class AdventuresController < ApplicationController
  skip_before_action :require_login, only: [:new]
  before_action :set_adventure, only: [:show, :destroy]

  # GET /adventures/new - serves the SPA page for creating an adventure
  def new
    render layout: 'application'
  end

  # GET /adventures - returns the current user's ongoing adventures as JSON
  def index
    adventures = policy_scope(Adventure)
                   .includes(story_state: :story)
                   .order(updated_at: :desc)

    render json: adventures.map { |a| adventure_summary(a) }
  end

  # GET /adventures/:id - serves the SPA page OR returns JSON for the API
  def show
    authorize(@adventure)

    respond_to do |format|
      format.html { render layout: 'application' }
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
      return render json: { error: 'This story has no states yet' }, status: :unprocessable_entity
    end

    snapshot = {
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
      character_class: sheet.character_class
    }

    max_hp = compute_starting_hp(sheet)

    @adventure = Adventure.new(
      user: current_user,
      sheet_id: sheet.id,
      story_state: initial_state,
      character_snapshot: snapshot,
      character_gold: 0,
      character_hp: max_hp,
      character_max_hp: max_hp,
      character_effects: nil,
      character_items: nil
    )

    if @adventure.save
      render json: adventure_json(@adventure), status: :created
    else
      render json: { errors: @adventure.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /adventures/:id
  def destroy
    authorize(@adventure)
    @adventure.destroy!
    render json: { message: 'Adventure deleted' }, status: :ok
  end

  private

  def set_adventure
    @adventure = Adventure.find(params[:id])
  end

  def adventure_summary(adventure)
    snapshot = adventure.character_snapshot || {}
    {
      id: adventure.id,
      character_name: snapshot['name'] || adventure.sheet.name,
      story_title: adventure.story_state.story.title,
      character_gold: adventure.character_gold,
      created_at: adventure.created_at,
      updated_at: adventure.updated_at
    }
  end

  def adventure_json(adventure)
    {
      id: adventure.id,
      character_snapshot: adventure.character_snapshot,
      story_state: adventure.story_state,
      story: adventure.story_state.story,
      character_gold: adventure.character_gold,
      character_hp: adventure.character_hp,
      character_max_hp: adventure.character_max_hp,
      character_effects: adventure.character_effects,
      character_items: adventure.character_items
    }
  end

  # Compute level-1 starting HP: max hit die + CON modifier
  def compute_starting_hp(sheet)
    hit_die_map = {
      'barbarian' => 12, 'bard' => 8, 'cleric' => 8, 'druid' => 8,
      'fighter' => 10, 'monk' => 8, 'paladin' => 10, 'ranger' => 10,
      'rogue' => 8, 'sorcerer' => 6, 'wizard' => 6
    }

    race_con_mod = {
      'dwarf' => 2, 'elf' => -2, 'gnome' => 2,
      'halfling' => 0, 'human' => 0, 'half_elf' => 0, 'half_orc' => 0
    }

    hit_die = hit_die_map[sheet.character_class] || 8
    racial_con = race_con_mod[sheet.race] || 0
    flexible_con = sheet.racial_bonus_attribute == 'constitution' ? 2 : 0
    final_con = sheet.constitution + racial_con + flexible_con
    con_modifier = ((final_con - 10).to_f / 2).floor

    [hit_die + con_modifier, 1].max
  end
end
