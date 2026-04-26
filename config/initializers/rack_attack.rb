# frozen_string_literal: true

class SafeRackAttackStore
  def initialize(store)
    @store = store
  end

  def increment(name, amount = 1, **options)
    safe("rack_attack_increment", fallback: nil, context: { key: name }) do
      @store.increment(name, amount, **options)
    end
  end

  def read(name, **options)
    safe("rack_attack_read", fallback: nil, context: { key: name }) do
      @store.read(name, **options)
    end
  end

  def write(name, value, **options)
    safe("rack_attack_write", fallback: true, context: { key: name }) do
      @store.write(name, value, **options)
    end
  end

  def delete(name, **options)
    safe("rack_attack_delete", fallback: nil, context: { key: name }) do
      @store.delete(name, **options)
    end
  end

  def delete_matched(*args, **options)
    safe("rack_attack_delete_matched", fallback: nil, context: {}) do
      @store.delete_matched(*args, **options)
    end
  end

  private

  def safe(event, fallback:, context:)
    yield
  rescue Redis::BaseError, IOError, SystemCallError, Timeout::Error => e
    DungeonMaster::FloodControl.record_fail_open(event, exception: e, context: context)
    fallback
  end
end

module RackAttackConfig
  DM_ENDPOINTS = %r{\A/adventures/\d+/messages(?:/(roll|initiative))?\z}.freeze
  USER_RATE_LIMIT = ENV.fetch("DM_USER_HTTP_RATE_LIMIT", "12").to_i
  USER_RATE_PERIOD = ENV.fetch("DM_USER_HTTP_RATE_PERIOD_SECONDS", "60").to_i
  IP_RATE_LIMIT = ENV.fetch("DM_IP_HTTP_RATE_LIMIT", "120").to_i
  IP_RATE_PERIOD = ENV.fetch("DM_IP_HTTP_RATE_PERIOD_SECONDS", "60").to_i
end

Rack::Attack.cache.store = SafeRackAttackStore.new(
  ActiveSupport::Cache::RedisCacheStore.new(
    url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"),
    namespace: "rack_attack"
  )
)

class Rack::Attack
  def self.dm_submit_request?(req)
    req.post? && req.path.match?(RackAttackConfig::DM_ENDPOINTS)
  end

  throttle("dm/user", limit: RackAttackConfig::USER_RATE_LIMIT, period: RackAttackConfig::USER_RATE_PERIOD) do |req|
    next unless dm_submit_request?(req)

    user_id = req.session["user_id"]
    "user:#{user_id}" if user_id.present?
  end

  throttle("dm/ip", limit: RackAttackConfig::IP_RATE_LIMIT, period: RackAttackConfig::IP_RATE_PERIOD) do |req|
    next unless dm_submit_request?(req)

    "ip:#{req.ip}"
  end

  self.throttled_responder = lambda do |request|
    matched = request.env["rack.attack.matched"].to_s
    reason = matched.include?("dm/user") ? "user_rate" : "ip_rate"
    retry_after = (request.env["rack.attack.match_data"] || {})[:period].to_i

    headers = {
      "Content-Type" => "application/json",
      "X-RateLimit-Reason" => reason
    }
    headers["Retry-After"] = retry_after.to_s if retry_after.positive?

    body = {
      error: "You are sending actions too quickly. Wait a moment and try again.",
      error_code: reason
    }.to_json

    [429, headers, [body]]
  end
end
