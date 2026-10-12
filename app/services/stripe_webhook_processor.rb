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
      # Not every flow goes through checkout, so creation is synced here too.
      handle_subscription_changed!
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

  def handle_subscription_changed!
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
    profile = find_profile_by_customer(invoice.customer)
    return if profile.nil?

    started_at = delinquency_started_at(profile)
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
      started_at = delinquency_started_at(profile)
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
    period_end_unix = subscription_period_end_unix(subscription)
    if missing_timestamp?(period_end_unix) && refetchable?(subscription)
      period_end_unix = subscription_period_end_unix(StripeGateway.retrieve_subscription(subscription.id))
    end
    return nil if missing_timestamp?(period_end_unix)

    Time.zone.at(period_end_unix.to_i)
  end

  def missing_timestamp?(unix_time)
    unix_time.nil? || unix_time.to_i <= 0
  end

  def refetchable?(subscription)
    subscription.respond_to?(:id) && subscription.id.present?
  end

  # Newer Stripe API versions put current_period_end on the items instead of the subscription.
  def subscription_period_end_unix(subscription)
    root_period_end = read_period_end_unix(subscription)
    return root_period_end if root_period_end

    subscription.items&.data&.each do |item|
      item_period_end = read_period_end_unix(item)
      return item_period_end if item_period_end
    end

    nil
  end

  def read_period_end_unix(stripe_object)
    return nil unless stripe_object

    if stripe_object.respond_to?(:current_period_end)
      period_end = stripe_object.current_period_end
      return period_end.to_i if period_end.present?
    end

    if stripe_object.respond_to?(:[])
      period_end = stripe_object[:current_period_end].presence || stripe_object["current_period_end"].presence
      return period_end.to_i if period_end.present?
    end

    nil
  end

  def delinquency_started_at(profile)
    profile.delinquent_since || Time.current
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
