# app/policies/application_policy.rb
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user   = user   # <- comes from ApplicationController#pundit_user
    @record = record
  end

  def index?
    false
  end

  def show?
    false
  end

  def create?
    false
  end

  def new?
    create?
  end

  def update?
    false
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  # Optional: every policy can ask the user if they have a permission
  def allow?(action)
    user&.can?(action)
  end

  class Scope
    attr_reader :user, :scope

    def initialize(user, scope)
      @user  = user
      @scope = scope
    end

    def resolve
      scope.all
    end
  end
end

# class ApplicationPolicy
#   attr_reader :user, :record

#   def initialize(user, record)
#     @user = user
#     @record = record
#   end

#   # Admin bypass: allow admins to do anything unless overridden
#   def index?
#     admin?
#   end

#   def show?
#     admin?
#   end

#   def create?
#     admin?
#   end

#   def new?
#     create?
#   end

#   def update?
#     admin?
#   end

#   def edit?
#     update?
#   end

#   def destroy?
#     admin?
#   end

#   private

#   def admin?
#     user&.admin?
#   end

#   class Scope
#     attr_reader :user, :scope

#     def initialize(user, scope)
#       @user = user
#       @scope = scope
#     end

#     def resolve
#       if user&.admin?
#         scope.all
#       else
#         scope.none
#       end
#     end
#   end
# end
#
