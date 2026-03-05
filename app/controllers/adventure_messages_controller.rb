class AdventureMessagesController < ApplicationController
  before_action :set_adventure
  before_action -> { authorize(@adventure, :show?) }

  # GET /adventures/:adventure_id/messages
  def index
    messages = @adventure.adventure_messages.chronological
    render json: messages.map { |m| message_json(m) }
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

    if async_pipeline?
      player_msg = service.prepare_prompt(player_input)
      PipelineJob.perform_later(@adventure.id, player_msg.id, player_input, mode, current_user.id)
      render json: { async: true, messages: [message_json(player_msg)] }, status: :accepted
    else
      result = service.process_player_prompt(player_input, mode: mode)
      render json: { messages: result[:messages].map { |m| message_json(m) } }
    end
  end

  # POST /adventures/:adventure_id/messages/initiative
  def initiative
    player_initiative = params[:initiative].to_i
    unless (1..40).include?(player_initiative)
      return render json: { error: "Initiative must be between 1 and 40" }, status: :unprocessable_entity
    end

    service = dm_service

    if async_pipeline?
      init_msg = service.prepare_initiative(player_initiative)
      InitiativePipelineJob.perform_later(@adventure.id, init_msg.id, player_initiative, current_user.id) if defined?(InitiativePipelineJob)
      render json: { async: true, messages: [message_json(init_msg)] }, status: :accepted
    else
      result = service.process_initiative_result(player_initiative)
      render json: { messages: result[:messages].map { |m| message_json(m) } }
    end
  end

  # POST /adventures/:adventure_id/messages/roll
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

    if async_pipeline?
      roll_msg = service.prepare_roll(rolls)
      roll_text = service.send(:format_roll_results, rolls)
      RollPipelineJob.perform_later(@adventure.id, roll_msg.id, roll_text, current_user.id)
      render json: { async: true, messages: [message_json(roll_msg)] }, status: :accepted
    else
      result = service.process_roll_result(rolls)
      render json: { messages: result[:messages].map { |m| message_json(m) } }
    end
  end

  private

  def set_adventure
    @adventure = Adventure.find(params[:adventure_id])
  end

  def dm_service
    DungeonMasterService.new(@adventure, user: current_user)
  end

  def async_pipeline?
    DmConfig.instance.get("async_pipeline") == true
  end

  def message_json(message)
    DungeonMasterService.message_json(message, admin: current_user&.admin?)
  end
end
