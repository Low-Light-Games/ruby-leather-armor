# frozen_string_literal: true

class AdventureChannel < ApplicationCable::Channel
  def subscribed
    adventure = Adventure.find_by(id: params[:adventure_id])

    if adventure && adventure.user_id == current_user.id
      stream_for adventure
    else
      reject
    end
  end
end
