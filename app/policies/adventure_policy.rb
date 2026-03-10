class AdventurePolicy < ApplicationPolicy
  def index?
    true # All authenticated users can list their own adventures
  end

  def show?
    admin? || owner?
  end

  def create?
    true # All authenticated users can create adventures
  end

  def destroy?
    admin? || owner?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.admin?
        scope.all
      else
        scope.kept.where(user_id: user.id)
      end
    end
  end
end
