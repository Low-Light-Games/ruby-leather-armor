class ApplicationController < ActionController::Base
  before_action :require_login
  before_action :set_sentry_user

  private

  def set_sentry_user
    return unless defined?(Sentry) && current_user

    Sentry.set_user(id: current_user.id, email: current_user.email)
  end

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def require_login
    unless current_user
      render json: { error: 'Authentication required' }, status: :unauthorized
    end
  end

  def authorize(record, query = nil)
    # Handle symbol records (like :admin)
    if record.is_a?(Symbol)
      policy_class = "#{record.to_s.camelize}Policy".constantize
      policy = policy_class.new(current_user, nil)
    else
      policy_class = "#{record.class.name}Policy".constantize
      policy = policy_class.new(current_user, record)
    end
    
    query ||= action_name.to_s + '?'
    
    unless policy.public_send(query)
      render json: { error: 'Access denied' }, status: :forbidden
      return
    end
  end

  def policy_scope(scope)
    policy_class = "#{scope.name}Policy::Scope".constantize
    policy_scope = policy_class.new(current_user, scope)
    policy_scope.resolve
  end

  helper_method :current_user
end
