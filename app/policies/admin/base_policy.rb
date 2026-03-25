module Admin
  class BasePolicy < ApplicationPolicy
    # Common rule: only system admins can access admin namespace
    def admin_only
      user&.admin?
    end

    # Fallback deny-all (optional)
    def method_missing(name, *args)
      admin_only
    end

    def respond_to_missing?(name, include_private = false)
      true
    end
  end
end
