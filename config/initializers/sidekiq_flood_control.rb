# frozen_string_literal: true

return unless defined?(Sidekiq)

class DmFloodControlServerMiddleware
  def call(_worker, job, _queue)
    yield

    admission = FloodControl.extract_prompt_admission(job)
    FloodControl.release_prompt_submission(admission)
  end
end

Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.add DmFloodControlServerMiddleware
  end

  config.death_handlers << lambda do |job, _exception|
    admission = FloodControl.extract_prompt_admission(job)
    FloodControl.release_prompt_submission(admission)
  end
end
