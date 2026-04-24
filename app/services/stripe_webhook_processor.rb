# frozen_string_literal: true

require "digest"

class StripeWebhookProcessor
  DELINQUENT_STATUSES = %w[past_due unpaid incomplete_expired].freeze
  ACTIVE_STATUSES = %w[active trialing].freeze

  def initialize(event:)
    @event = event
  end

  def call
    return if duplicate_event?

    process_event!
    persist_processed_event!
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  private

  attr_reader :event

  def duplicate_event?
    StripeWebhookEvent.exists?(stripe_event_id: event.id)
  end

  def process_event!
    case event.type
    when "checkout.session.completed"
      handle_checkout_completed!
    when "customer.subscription.updated", "customer.subscription.created"
      # Created and updated payloads are both full Subscription objects; checkout may not run for all flows.
      handle_subscription_updated!
    when "customer.subscription.deleted"
      handle_subscription_deleted!
    when "invoice.payment_failed"
      handle_invoice_payment_failed!
    end
  end

  def handle_checkout_completed!
    session = event.data.object
    subscription_id = session.subscription
    return if subscription_id.blank?

    profile = find_or_build_profile(customer_id: session.customer, metadata: session.metadata)
    return if profile.nil?

    subscription = StripeGateway.retrieve_subscription(subscription_id)
    apply_subscription!(profile: profile, subscription: subscription)
  end

  def handle_subscription_updated!
    subscription = event.data.object
    profile = find_profile_by_customer(subscription.customer)
    return if profile.nil?

    apply_subscription!(profile: profile, subscription: subscription)
  end

  def handle_subscription_deleted!
    subscription = event.data.object
    profile = find_profile_by_customer(subscription.customer)
    return if profile.nil?

    profile.update!(
      plan_key: "free",
      stripe_subscription_id: subscription.id,
      stripe_subscription_status: subscription.status,
      stripe_price_id: nil,
      stripe_current_period_end: period_end_for(subscription),
      delinquent_since: nil,
      grace_period_ends_at: nil
    )
  end

  def handle_invoice_payment_failed!
    invoice = event.data.object
    customer_id = invoice.customer
    profile = find_profile_by_customer(customer_id)
    return if profile.nil?

    started_at = profile.delinquent_since || Time.current
    profile.update!(
      stripe_subscription_status: "past_due",
      delinquent_since: started_at,
        grace_period_ends_at: started_at + grace_period_duration
    )
  end

  def apply_subscription!(profile:, subscription:)
    price_id = subscription_price_id(subscription)
    mapped_plan = StripePlans.find_by_price_id(price_id)
    status = subscription.status
    period_end = period_end_for(subscription)

    if DELINQUENT_STATUSES.include?(status)
      started_at = profile.delinquent_since || Time.current
      attrs = delinquent_subscription_attributes(subscription, status, price_id, period_end, started_at)
      attrs[:plan_key] = "free" if profile.grace_expired?
      profile.update!(attrs)
      return
    end

    profile.update!(
      plan_key: mapped_plan&.key || "free",
      stripe_subscription_id: subscription.id,
      stripe_subscription_status: status,
      stripe_price_id: price_id,
      stripe_current_period_end: period_end,
      delinquent_since: nil,
      grace_period_ends_at: nil
    )
  end

  def find_or_build_profile(customer_id:, metadata:)
    profile = find_profile_by_customer(customer_id)
    return profile if profile.present?

    user = User.find_by(id: metadata&.[]("user_id"))
    return nil if user.nil?

    profile = user.stripe_profile || user.create_stripe_profile!
    profile.update!(stripe_customer_id: customer_id) if customer_id.present?
    profile
  end

  def find_profile_by_customer(customer_id)
    return nil if customer_id.blank?

    UserStripeProfile.find_by(stripe_customer_id: customer_id)
  end

  def persist_processed_event!
    StripeWebhookEvent.create!(
      stripe_event_id: event.id,
      event_type: event.type,
      processed_at: Time.current,
      payload_digest: Digest::SHA256.hexdigest(event.to_json)
    )
  end

  def subscription_price_id(subscription)
    subscription.items&.data&.first&.price&.id
  end

  def period_end_for(subscription)
    ts = subscription_period_end_unix(subscription)
    if (ts.nil? || ts.to_i <= 0) && subscription.respond_to?(:id) && subscription.id.present?
      subscription = StripeGateway.retrieve_subscription(subscription.id)
      ts = subscription_period_end_unix(subscription)
    end
    return nil if ts.nil? || ts.to_i <= 0

    Time.zone.at(ts.to_i)
  end

  # Stripe API 2025-03-31+ (Basil): current_period_end lives on subscription items, not the root.
  # Older accounts still return it on the subscription object — support both.
  def subscription_period_end_unix(subscription)
    unix = read_period_end_unix(subscription)
    return unix if unix

    subscription.items&.data&.each do |item|
      u = read_period_end_unix(item)
      return u if u
    end

    nil
  end

  def read_period_end_unix(obj)
    return nil unless obj

    if obj.respond_to?(:current_period_end)
      v = obj.current_period_end
      return v.to_i if v.present?
    end

    if obj.respond_to?(:[])
      v = obj[:current_period_end].presence || obj["current_period_end"].presence
      return v.to_i if v.present?
    end

    nil
  end

  def grace_period_duration
    DmConfig.instance.stripe_grace_period_days.days
  end

  def delinquent_subscription_attributes(subscription, status, price_id, period_end, started_at)
    {
      stripe_subscription_id: subscription.id,
      stripe_subscription_status: status,
      stripe_price_id: price_id,
      stripe_current_period_end: period_end,
      delinquent_since: started_at,
      grace_period_ends_at: started_at + grace_period_duration
    }
  end
end
