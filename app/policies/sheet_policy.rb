class SheetPolicy < ApplicationPolicy
  def index?
    true # All authenticated users can see their sheets
  end

  def show?
    admin? || owner?
  end

  def create?
    user&.paid_or_admin?
  end

  def update?
    return false if record&.starter?

    admin? || (owner? && user&.paid_or_admin?)
  end

  def destroy?
    return false if record&.starter?

    admin? || owner?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.admin?
        scope.all.includes(:user)
      else
        scope.where(user_id: user.id)
      end
    end
  end
end
