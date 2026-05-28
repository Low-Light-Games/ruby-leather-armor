# frozen_string_literal: true

module AdventureScoping
  extend ActiveSupport::Concern

  private

  def adventure_scope
    current_user&.admin? ? Adventure.all : Adventure.kept
  end
end
