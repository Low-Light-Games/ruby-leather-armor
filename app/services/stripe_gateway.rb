# frozen_string_literal: true

module StripeGateway
  module_function

  def create_customer(email:)
    configure!
    Stripe::Customer.create(email: email)
  end

  def create_checkout_session(params)
    configure!
    Stripe::Checkout::Session.create(params)
  end

  def create_billing_portal_session(params)
    configure!
    Stripe::BillingPortal::Session.create(params)
  end

  def construct_event(payload:, signature:, webhook_secret:)
    Stripe::Webhook.construct_event(payload, signature, webhook_secret)
  end

  def retrieve_subscription(subscription_id)
    configure!
    id = coerce_subscription_id(subscription_id)
    return if id.blank?

    # stripe-ruby v19+: the second positional hash is treated as request *options* (api key, headers),
    # not query params—`expand` there becomes a header value and can trigger `strip` on an Array.
    # Pass `id` and `expand` in a single Hash so they become retrieve params (see APIResource#retrieve).
    Stripe::Subscription.retrieve(
      { id: id, expand: %w[items.data] }
    )
  end

  def retrieve_checkout_session(session_id)
    configure!
    Stripe::Checkout::Session.retrieve(session_id)
  end

  def configure!
    Stripe.api_key = ENV.fetch("STRIPE_SECRET_KEY")
  end

  # :nodoc: — resolve String / expandable object / webhook quirks to a subscription id.
  def coerce_subscription_id(raw)
    case raw
    when nil, "" then nil
    when String then raw.strip.presence
    when Array then coerce_subscription_id(raw.first)
    when Hash then coerce_subscription_id(raw[:id] || raw["id"])
    else
      coerce_subscription_id(raw.respond_to?(:id) ? raw.id : nil)
    end
  end
  private :coerce_subscription_id
end
