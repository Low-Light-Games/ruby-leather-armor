class StripeWebhooksController < ApplicationController
  skip_before_action :require_login
  skip_before_action :verify_authenticity_token

  def create
    webhook_secret = ENV.fetch("STRIPE_WEBHOOK_SECRET")
    signature = request.headers["Stripe-Signature"]
    event = StripeGateway.construct_event(
      payload: request.raw_post,
      signature: signature,
      webhook_secret: webhook_secret
    )

    StripeWebhookProcessor.new(event: event).call
    head :ok
  rescue Stripe::SignatureVerificationError => e
    ApplicationErrorReporter.notify(e, context: { source: "stripe_webhook_signature" })
    render json: { error: "Invalid webhook signature." }, status: :bad_request
  rescue KeyError => e
    ApplicationErrorReporter.notify(e, context: { source: "stripe_webhook_missing_secret" })
    render json: { error: e.message }, status: :internal_server_error
  rescue JSON::ParserError => e
    ApplicationErrorReporter.notify(e, context: { source: "stripe_webhook_json_parse" })
    render json: { error: "Invalid webhook payload." }, status: :bad_request
  rescue StandardError => e
    ApplicationErrorReporter.notify(e, context: { source: "stripe_webhook_create" })
    render json: { error: "Webhook processing failed." }, status: :internal_server_error
  end
end
