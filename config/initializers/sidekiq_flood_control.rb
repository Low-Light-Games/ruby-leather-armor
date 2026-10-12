# frozen_string_literal: true

return unless defined?(Sidekiq)

class DmFloodControlServerMiddleware
  def call(_worker, job, _queue)
    yield

    # Not in an ensure: a retrying job keeps its slot until it succeeds or dies.
    FloodControl.release_prompt_submission_for_job(job)
  end
end

Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.add DmFloodControlServerMiddleware
  end

  config.death_handlers << ->(job, _exception) { FloodControl.release_prompt_submission_for_job(job) }
end
