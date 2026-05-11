# frozen_string_literal: true

class PromptSubmissionHeartbeatJob < ApplicationJob
  queue_as :default

  def perform(admission)
    return unless FloodControl.prompt_admission?(admission)

    FloodControl.refresh_prompt_submission(admission)
  end
end
