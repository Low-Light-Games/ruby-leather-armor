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
    # Ensure subscription items are expanded (Basil+ API exposes billing period on items).
    Stripe::Subscription.retrieve(
      subscription_id,
      { expand: %w[items.data] }
    )
  end

  def retrieve_checkout_session(session_id)
    configure!
    Stripe::Checkout::Session.retrieve(session_id)
  end

  def configure!
    Stripe.api_key = ENV.fetch("STRIPE_SECRET_KEY")
  end
end
