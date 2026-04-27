# frozen_string_literal: true

class PromptSubmissionHeartbeatJob < ApplicationJob
  queue_as :default

  def perform(admission)
    return unless DungeonMaster::FloodControl.prompt_admission?(admission)

    DungeonMaster::FloodControl.refresh_prompt_submission(admission)
  end
end
