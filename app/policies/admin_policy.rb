class AdminPolicy < ApplicationPolicy
  def all_sheets?
    admin?
  end
end
