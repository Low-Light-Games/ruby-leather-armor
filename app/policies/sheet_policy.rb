class SheetPolicy < ApplicationPolicy
  def index?
    true # All authenticated users can see their sheets
  end

  def show?
    admin? || owner?
  end

  def create?
    true # All authenticated users can create sheets
  end

  def update?
    admin? || owner?
  end

  def destroy?
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
