# frozen_string_literal: true

class NameChangeRequestPolicy < ApplicationPolicy
  def index?
    admin_or_reviewer?
  end

  def show?
    admin_or_reviewer?
  end

  def approve?
    admin_or_reviewer?
  end

  def reject?
    admin_or_reviewer?
  end

  private

  def admin_or_reviewer?
    return false unless user
    return true if user.is_a?(AdminUser) || user.is_a?(Admin)

    user.respond_to?(:has_role?) &&
      (user.has_role?(:admin) || user.has_role?(:reviewer))
  end
end
