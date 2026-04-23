class SubscriptionsController < ApplicationController
  def plans
    presenter = SubscriptionPlansPresenter.new(user: current_user)
    @plans_payload = presenter.plans_payload
    @current_plan_key = presenter.current_plan_key
  end

  def success
    @preview_mode = resolve_preview_mode
    return if @preview_mode.present?

    unless valid_success_session?
      redirect_to plans_path, alert: "Subscription confirmation is missing or invalid."
    end
  end

  def checkout
    plan = resolve_checkout_plan
    return if performed?

    profile = current_user.stripe_profile || current_user.create_stripe_profile!
    ensure_customer_id!(profile)

    session = StripeGateway.create_checkout_session(
      mode: "subscription",
      customer: profile.stripe_customer_id,
      line_items: [{ price: plan.stripe_price_id, quantity: 1 }],
      success_url: "#{request.base_url}/subscription/success?session_id={CHECKOUT_SESSION_ID}",
      cancel_url: "#{request.base_url}/plans?checkout=canceled",
      client_reference_id: current_user.id.to_s,
      metadata: {
        user_id: current_user.id.to_s,
        plan_key: plan.key
      }
    )

    render json: { checkout_url: session.url }
  rescue KeyError => e
    render json: { error: e.message }, status: :unprocessable_content
  rescue StandardError => e
    ApplicationErrorReporter.notify(e, context: { source: "subscriptions_checkout", user_id: current_user.id })
    render json: { error: "Unable to start checkout right now." }, status: :internal_server_error
  end

  def portal
    profile = current_user.stripe_profile
    if profile.nil? || profile.stripe_customer_id.blank?
      render json: { error: "No Stripe customer is linked to this account yet." }, status: :unprocessable_content
      return
    end

    session = StripeGateway.create_billing_portal_session(
      customer: profile.stripe_customer_id,
      return_url: "#{request.base_url}/plans"
    )

    render json: { portal_url: session.url }
  rescue StandardError => e
    ApplicationErrorReporter.notify(e, context: { source: "subscriptions_portal", user_id: current_user.id })
    render json: { error: "Unable to open billing portal right now." }, status: :internal_server_error
  end

  private

  def resolve_checkout_plan
    plan = StripePlans.fetch(params[:plan_key].to_s)
    if plan.free? || plan.stripe_price_id.blank?
      render json: { error: "Select a paid plan to start checkout." }, status: :unprocessable_content
      return
    end
    plan
  end

  def ensure_customer_id!(profile)
    return if profile.stripe_customer_id.present?

    customer = StripeGateway.create_customer(email: current_user.email)
    profile.update!(stripe_customer_id: customer.id)
  end

  def resolve_preview_mode
    return nil unless current_user&.admin?

    preview_mode = params[:preview].to_s
    return preview_mode if %w[syncing confirmed pending].include?(preview_mode)

    nil
  end

  def valid_success_session?
    session_id = params[:session_id].to_s
    return false if session_id.blank?

    checkout_session = StripeGateway.retrieve_checkout_session(session_id)
    return false unless checkout_session&.mode == "subscription"

    customer_matches = current_user.stripe_profile&.stripe_customer_id.present? &&
      checkout_session.customer.to_s == current_user.stripe_profile.stripe_customer_id
    client_reference_matches = checkout_session.client_reference_id.to_s == current_user.id.to_s

    customer_matches || client_reference_matches
  rescue StandardError => e
    ApplicationErrorReporter.notify(e, context: { source: "subscriptions_success_session_validation", user_id: current_user.id, session_id: session_id })
    false
  end
end
