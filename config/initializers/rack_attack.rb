# frozen_string_literal: true

class SafeRackAttackStore
  def initialize(store)
    @store = store
  end

  def increment(name, amount = 1, **options)
    @store.increment(name, amount, **options)
  rescue Redis::BaseError, IOError, SystemCallError, Timeout::Error => e
    DungeonMaster::FloodControl.record_fail_open("rack_attack_increment", exception: e, context: { key: name })
    nil
  end

  def read(name, **options)
    @store.read(name, **options)
  rescue Redis::BaseError, IOError, SystemCallError, Timeout::Error => e
    DungeonMaster::FloodControl.record_fail_open("rack_attack_read", exception: e, context: { key: name })
    nil
  end

  def write(name, value, **options)
    @store.write(name, value, **options)
  rescue Redis::BaseError, IOError, SystemCallError, Timeout::Error => e
    DungeonMaster::FloodControl.record_fail_open("rack_attack_write", exception: e, context: { key: name })
    true
  end

  def delete(name, **options)
    @store.delete(name, **options)
  rescue Redis::BaseError, IOError, SystemCallError, Timeout::Error => e
    DungeonMaster::FloodControl.record_fail_open("rack_attack_delete", exception: e, context: { key: name })
    nil
  end

  def delete_matched(*args, **options)
    @store.delete_matched(*args, **options)
  rescue Redis::BaseError, IOError, SystemCallError, Timeout::Error => e
    DungeonMaster::FloodControl.record_fail_open("rack_attack_delete_matched", exception: e, context: {})
    nil
  end
end

Rack::Attack.cache.store = SafeRackAttackStore.new(
  ActiveSupport::Cache::RedisCacheStore.new(
    url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"),
    namespace: "rack_attack"
  )
)

class Rack::Attack
  DM_ENDPOINTS = %r{\A/adventures/\d+/messages(?:/(roll|initiative))?\z}.freeze
  USER_RATE_LIMIT = ENV.fetch("DM_USER_HTTP_RATE_LIMIT", "12").to_i
  USER_RATE_PERIOD = ENV.fetch("DM_USER_HTTP_RATE_PERIOD_SECONDS", "60").to_i
  IP_RATE_LIMIT = ENV.fetch("DM_IP_HTTP_RATE_LIMIT", "120").to_i
  IP_RATE_PERIOD = ENV.fetch("DM_IP_HTTP_RATE_PERIOD_SECONDS", "60").to_i

  def self.dm_submit_request?(req)
    req.post? && req.path.match?(DM_ENDPOINTS)
  end

  throttle("dm/user", limit: USER_RATE_LIMIT, period: USER_RATE_PERIOD) do |req|
    next unless dm_submit_request?(req)

    user_id = req.session["user_id"]
    "user:#{user_id}" if user_id.present?
  end

  throttle("dm/ip", limit: IP_RATE_LIMIT, period: IP_RATE_PERIOD) do |req|
    next unless dm_submit_request?(req)

    "ip:#{req.ip}"
  end

  self.throttled_responder = lambda do |request|
    matched = request.env["rack.attack.matched"].to_s
    error_code = matched.include?("dm/user") ? "user_rate" : "ip_rate"
    reason = matched.include?("dm/user") ? "user_rate" : "ip_rate"
    retry_after = (request.env["rack.attack.match_data"] || {})[:period].to_i

    headers = {
      "Content-Type" => "application/json",
      "X-RateLimit-Reason" => reason
    }
    headers["Retry-After"] = retry_after.to_s if retry_after.positive?

    body = {
      error: "You are sending actions too quickly. Wait a moment and try again.",
      error_code: error_code
    }.to_json

    [429, headers, [body]]
  end
end
