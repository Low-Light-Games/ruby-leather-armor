class AdventureMessagesController < ApplicationController
  before_action :set_adventure
  before_action -> { authorize(@adventure, :show?) }
  before_action -> { authorize(@adventure, :pipeline?) }, only: %i[create initiative roll]
  before_action :check_ban
  before_action :reject_ended_adventure!, only: %i[create initiative roll]

  # GET /adventures/:adventure_id/messages
  def index
    messages = @adventure.adventure_messages.chronological
    render json: {
      messages: messages.map { |m| message_json(m) },
      pipeline_running: PipelineRegistryEntry.active_for?(@adventure)
    }
  end

  # POST /adventures/:adventure_id/messages
  def create
    player_input = params[:content]&.strip

    if player_input.blank?
      return render json: { error: "Message cannot be empty" }, status: :unprocessable_entity
    end

    if player_input.length > 500
      return render json: { error: "Message too long (max 500 characters)" }, status: :unprocessable_entity
    end

    mode = params[:mode]&.strip
    service = dm_service
    admission = DungeonMaster::FloodControl.admit_prompt_submission(user_id: current_user.id)
    player_msg = service.prepare_prompt(player_input)
    PipelineJob.perform_later(
      @adventure.id,
      player_msg.id,
      player_input,
      mode,
      current_user.id,
      { "prompt_admission" => admission }
    )
    render json: { async: true, messages: [message_json(player_msg)] }, status: :accepted
  rescue DungeonMaster::FloodControl::PromptBacklogExceeded => e
    render_limit_error(e.message, code: "prompt_backlog", reason: "prompt_backlog")
  rescue StandardError
    DungeonMaster::FloodControl.release_prompt_submission(admission)
    raise
  end

  # POST /adventures/:adventure_id/messages/initiative
  def initiative
    unless DungeonMaster::Rolls::AdventureMechanicalState.latest_pending_initiative_request(@adventure)
      return render json: { error: "There is no pending initiative request to resolve.", error_code: "initiative_not_requested" }, status: :unprocessable_entity
    end

    player_initiative = params[:initiative].to_i
    unless (1..40).include?(player_initiative)
      return render json: { error: "Initiative must be between 1 and 40" }, status: :unprocessable_entity
    end

    service = dm_service

    init_msg = service.prepare_initiative(player_initiative)
    InitiativePipelineJob.perform_later(@adventure.id, init_msg.id, player_initiative, current_user.id)
    render json: { async: true, messages: [message_json(init_msg)] }, status: :accepted
  end

  # POST /adventures/:adventure_id/messages/roll
  def roll
    unless DungeonMaster::Rolls::AdventureMechanicalState.latest_pending_roll_request(@adventure)
      return render json: { error: "There is no pending roll request to resolve.", error_code: "roll_not_requested" }, status: :unprocessable_entity
    end

    rolls = if params[:rolls].present?
              Array(params[:rolls]).map do |r|
                { roll_value: r[:roll_value].to_i,
                  roll_description: r[:roll_description]&.strip || "unknown check",
                  resolution_method: r[:resolution_method]&.strip,
                  request_id: r[:request_id]&.strip.presence }
              end
            else
              [{ roll_value: params[:roll_value].to_i,
                 roll_description: params[:roll_description]&.strip || "unknown check",
                 resolution_method: params[:resolution_method]&.strip,
                 request_id: params[:request_id]&.strip.presence }]
            end

    invalid = rolls.find { |r| !(-100..100).include?(r[:roll_value]) }
    if invalid
      return render json: { error: "Roll value must be between -100 and 100" }, status: :unprocessable_entity
    end

    service = dm_service

    roll_msg = service.prepare_roll(rolls)
    roll_text = DungeonMaster::Rolls::RollResultsText.format(rolls)
    RollPipelineJob.perform_later(@adventure.id, roll_msg.id, roll_text, current_user.id)
    render json: { async: true, messages: [message_json(roll_msg)] }, status: :accepted
  end

  private

  def check_ban
    return unless current_user&.banned?

    render json: {
      banned: true,
      message: "Your account has been suspended. Contact appeals@leatheramor.io for assistance."
    }, status: :forbidden
  end

  def reject_ended_adventure!
    return unless @adventure.ended?

    render json: {
      error: "This adventure has ended and can no longer continue.",
      error_code: "adventure_ended"
    }, status: 422
  end

  def set_adventure
    @adventure = Adventure.kept.find(params[:adventure_id])
  end

  def dm_service
    DungeonMasterService.new(@adventure, user: current_user)
  end

  def message_json(message)
    DungeonMasterService.message_json(message, admin: current_user&.admin?)
  end

  def render_limit_error(message, code:, reason:)
    response.set_header("X-RateLimit-Reason", reason)
    render json: { error: message, error_code: code }, status: :too_many_requests
  end
end
