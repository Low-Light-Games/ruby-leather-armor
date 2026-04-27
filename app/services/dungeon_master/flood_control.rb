# frozen_string_literal: true

require 'connection_pool'
require 'securerandom'

module DungeonMaster
  # Redis-backed admission control for one in-flight prompt per user, with lease refresh support.
  module FloodControl
    extend self

    PROMPT_SLOT_TTL_SECONDS = ENV.fetch('DM_PROMPT_SLOT_TTL_SECONDS', '120').to_i
    PROMPT_SLOT_HEARTBEAT_SECONDS = ENV.fetch('DM_PROMPT_SLOT_HEARTBEAT_SECONDS', '30').to_i
    PROMPT_SLOT_HEARTBEAT_ATTEMPTS = ENV.fetch(
      'DM_PROMPT_SLOT_HEARTBEAT_ATTEMPTS',
      ((PROMPT_SLOT_TTL_SECONDS / PROMPT_SLOT_HEARTBEAT_SECONDS.to_f).ceil + 2).to_s
    ).to_i
    REDIS_NAMESPACE = ENV.fetch('DM_FLOOD_CONTROL_NAMESPACE', 'dm_flood_control')
    REDIS_POOL_SIZE = ENV.fetch('DM_FLOOD_CONTROL_REDIS_POOL_SIZE', ENV.fetch('RAILS_MAX_THREADS', '5')).to_i
    REDIS_POOL_TIMEOUT_SECONDS = ENV.fetch('DM_FLOOD_CONTROL_REDIS_POOL_TIMEOUT_SECONDS', '1').to_f

    RESERVE_PROMPT_SLOT_SCRIPT = <<~LUA
      if redis.call("EXISTS", KEYS[1]) == 1 then
        return 0
      end

      redis.call("SET", KEYS[1], ARGV[1], "EX", ARGV[2])
      return 1
    LUA

    REFRESH_PROMPT_SLOT_SCRIPT = <<~LUA
      if redis.call("GET", KEYS[1]) ~= ARGV[1] then
        return 0
      end

      redis.call("EXPIRE", KEYS[1], ARGV[2])
      return 1
    LUA

    RELEASE_PROMPT_SLOT_SCRIPT = <<~LUA
      if redis.call("GET", KEYS[1]) ~= ARGV[1] then
        return 0
      end

      redis.call("DEL", KEYS[1])
      return 1
    LUA

    class PromptBacklogExceeded < StandardError; end

    def admit_prompt_submission(user_id:)
      owner_token = SecureRandom.uuid
      key = prompt_slot_key(user_id)

      result = with_fail_open('prompt_backlog_reserve', user_id: user_id, fallback: :fail_open) do
        with_redis do |redis|
          redis.eval(
            RESERVE_PROMPT_SLOT_SCRIPT,
            keys: [key],
            argv: [owner_token, PROMPT_SLOT_TTL_SECONDS]
          )
        end
      end

      case result
      when 1
        { 'user_id' => user_id, 'owner_token' => owner_token }
      when 0
        raise PromptBacklogExceeded,
              'You already have an action in progress. Wait for it to finish before sending another.'
      end
    end

    def refresh_prompt_submission(admission)
      return false unless prompt_admission?(admission)

      with_fail_open('prompt_backlog_refresh', user_id: admission['user_id'], fallback: false) do
        with_redis do |redis|
          redis.eval(
            REFRESH_PROMPT_SLOT_SCRIPT,
            keys: [prompt_slot_key(admission['user_id'])],
            argv: [admission['owner_token'], PROMPT_SLOT_TTL_SECONDS]
          ) == 1
        end
      end
    end

    def release_prompt_submission(admission)
      return false unless prompt_admission?(admission)

      with_fail_open('prompt_backlog_release', user_id: admission['user_id'], fallback: false) do
        with_redis do |redis|
          redis.eval(
            RELEASE_PROMPT_SLOT_SCRIPT,
            keys: [prompt_slot_key(admission['user_id'])],
            argv: [admission['owner_token']]
          ) == 1
        end
      end
    end

    def with_prompt_submission_heartbeat(admission)
      return yield unless prompt_admission?(admission)

      return yield unless heartbeat_scheduling_supported?

      schedule_prompt_submission_heartbeats(admission)
      yield
    end

    def extract_prompt_admission(job_hash)
      raw_args = job_hash['args']
      wrapper = raw_args.is_a?(Array) ? raw_args.first : nil
      arguments = wrapper.is_a?(Hash) ? wrapper['arguments'] : raw_args
      return nil unless arguments.is_a?(Array)

      options = normalize_hash(arguments.last)
      admission = normalize_hash(options['prompt_admission'])
      return nil unless prompt_admission?(admission)

      admission
    rescue StandardError => e
      record_fail_open('prompt_backlog_extract', exception: e, context: {})
      nil
    end

    def prompt_admission?(admission)
      admission.is_a?(Hash) && admission['user_id'].present? && admission['owner_token'].present?
    end

    private

    def prompt_slot_key(user_id)
      "#{REDIS_NAMESPACE}:user:#{user_id}:prompt_slot"
    end

    def schedule_prompt_submission_heartbeats(admission)
      1.upto(PROMPT_SLOT_HEARTBEAT_ATTEMPTS) do |attempt|
        PromptSubmissionHeartbeatJob.set(wait: attempt * PROMPT_SLOT_HEARTBEAT_SECONDS.seconds).perform_later(admission)
      end
    rescue StandardError => e
      ApplicationErrorReporter.notify(
        e,
        context: {
          source: 'dm_flood_control_heartbeat_schedule',
          user_id: admission['user_id'],
          owner_token: admission['owner_token']
        }
      )
    end

    def redis_pool
      @redis_pool ||= ConnectionPool.new(size: REDIS_POOL_SIZE, timeout: REDIS_POOL_TIMEOUT_SECONDS) do
        Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1'))
      end
    end

    def with_redis(&)
      redis_pool.with(&)
    end

    def heartbeat_scheduling_supported?
      !ActiveJob::Base.queue_adapter.is_a?(ActiveJob::QueueAdapters::InlineAdapter)
    end

    def normalize_hash(value)
      return {} unless value.is_a?(Hash)

      value.each_with_object({}) do |(key, inner_value), normalized|
        next if key.to_s == '_aj_symbol_keys'

        normalized[key.to_s] = inner_value.is_a?(Hash) ? normalize_hash(inner_value) : inner_value
      end
    end

    def with_fail_open(event, user_id:, fallback:)
      yield
    rescue ConnectionPool::TimeoutError, Redis::BaseError, IOError, SystemCallError, Timeout::Error => e
      record_fail_open(event, exception: e, context: { user_id: user_id })
      fallback
    end

    def record_fail_open(event, exception:, context:)
      payload = context.merge(event: event, error_class: exception.class.name, error_message: exception.message)
      ActiveSupport::Notifications.instrument('dm.flood_control.fail_open', payload)
      Rails.logger.error("[DM flood_control fail_open] #{payload}")
      ApplicationErrorReporter.notify(exception, context: payload.merge(source: 'dm_flood_control_fail_open'))
    end
  end
end
