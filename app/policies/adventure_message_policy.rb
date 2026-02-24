class AdventureMessagePolicy < ApplicationPolicy
  # Access is controlled via the parent adventure's policy.
  # The controller authorizes via @adventure.show? so we don't need
  # per-message authorization, but we define the class for completeness.

  def index?
    adventure_accessible?
  end

  def create?
    adventure_accessible?
  end

  private

  def adventure_accessible?
    return false unless user.present?
    user.admin? || record.adventure.user_id == user.id
  end
end
