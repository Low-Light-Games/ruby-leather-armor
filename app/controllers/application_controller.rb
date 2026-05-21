class ApplicationController < ActionController::Base
  before_action :require_login
  before_action :set_sentry_user

  private

  def set_sentry_user
    return unless defined?(Sentry) && current_user

    Sentry.set_user(id: current_user.id, email: current_user.email)
  end

  def current_user
    @current_user ||= load_session_user || load_existing_guest_user
  end

  def load_session_user
    return nil unless session[:user_id]

    User.find_by(id: session[:user_id])
  end

  def load_existing_guest_user
    return nil if request.remote_ip.blank?

    Users::GuestFactory.find_for_ip(request.remote_ip)
  end

  def require_login
    return if current_user

    render json: { error: 'Authentication required' }, status: :unauthorized
  end

  def absorb_pending_guest_into(user)
    return false if user.nil? || user.guest?

    guest = Users::GuestFactory.find_for_ip(request.remote_ip)
    return false if guest.nil? || !guest.guest? || guest.id == user.id

    Users::AbsorbGuest.call(real_user: user, guest: guest)
  end

  def authorize(record, query = nil)
    if record.is_a?(Symbol)
      policy_class = "#{record.to_s.camelize}Policy".constantize
      policy = policy_class.new(current_user, nil)
    else
      policy_class = "#{record.class.name}Policy".constantize
      policy = policy_class.new(current_user, record)
    end

    query ||= "#{action_name}?"

    return if policy.public_send(query)

    render json: { error: 'Access denied' }, status: :forbidden
  end

  def policy_scope(scope)
    policy_class = "#{scope.name}Policy::Scope".constantize
    policy_scope = policy_class.new(current_user, scope)
    policy_scope.resolve
  end

  helper_method :current_user
end
