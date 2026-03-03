class AdventureMessagesController < ApplicationController
  before_action :set_adventure
  before_action -> { authorize(@adventure, :show?) }

  # GET /adventures/:adventure_id/messages
  # Returns conversation history for the adventure
  def index
    messages = @adventure.adventure_messages.chronological

    render json: messages.map { |m| message_json(m) }
  end

  # POST /adventures/:adventure_id/messages
  # Sends a player prompt through the DM pipeline
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
    result = service.process_player_prompt(player_input, mode: mode)

    render json: {
      messages: result[:messages].map { |m| message_json(m) }
    }
  end

  # POST /adventures/:adventure_id/messages/roll
  # Submits roll results (batched) for the DM to process.
  # Accepts either:
  #   - { rolls: [{ roll_value: 14, roll_description: "Swim check" }, ...] }  (batched)
  #   - { roll_value: 14, roll_description: "Swim check" }  (legacy single roll)
  def roll
    rolls = if params[:rolls].present?
              Array(params[:rolls]).map do |r|
                { roll_value: r[:roll_value].to_i, roll_description: r[:roll_description]&.strip || "unknown check" }
              end
            else
              [{ roll_value: params[:roll_value].to_i, roll_description: params[:roll_description]&.strip || "unknown check" }]
            end

    invalid = rolls.find { |r| !(1..100).include?(r[:roll_value]) }
    if invalid
      return render json: { error: "Roll value must be between 1 and 100" }, status: :unprocessable_entity
    end

    service = dm_service
    result = service.process_roll_result(rolls)

    render json: {
      messages: result[:messages].map { |m| message_json(m) }
    }
  end

  private

  def set_adventure
    @adventure = Adventure.find(params[:adventure_id])
  end

  def dm_service
    DungeonMasterService.new(@adventure, user: current_user)
  end

  def message_json(message)
    json = {
      id: message.id,
      role: message.role,
      content: message.content,
      message_type: message.message_type,
      metadata: message.metadata,
      created_at: message.created_at
    }
    if current_user&.admin? && message.role == "dm"
      json[:pipeline_run_id] = message.metadata&.dig("pipeline_run_id")
    end
    json
  end
end
