class AdventurePolicy < ApplicationPolicy
  def index?
    true # All authenticated users can list their own adventures
  end

  def show?
    admin? || owner?
  end

  # Sheet mutations (PATCH adventure_sheet, equip toggles): same gate as show — explicit verb for writes.
  def update?
    show?
  end

  # AI pipeline (prompt, rolls, initiative): same access as show, plus room under the user's usage cap.
  def pipeline?
    return false unless show?

    !user.usage_limit_reached?
  end

  def create?
    true # All authenticated users can create adventures
  end

  def destroy?
    admin? || owner?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      # Player routes use `Adventure.kept.find` on show; listing must not include
      # discarded rows or admins see ghosts in /adventures that 404 on open.
      if user.admin?
        scope.kept
      else
        scope.kept.where(user_id: user.id)
      end
    end
  end
end
