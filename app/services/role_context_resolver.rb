# app/services/role_context_resolver.rb
class RoleContextResolver
  ROLE_PRIORITY = %i[admin officer banking_agent partner_admin citizen guest].freeze

  def initialize(resource)
    @resource = resource
  end

  def current_role
    return :admin if admin?
    return :officer if officer?
    return :banking_agent if banking_agent?
    return :partner_admin if partner_admin?
    return :citizen if citizen?
    :guest
  end

  def has_role?(role)
    @resource.respond_to?(:has_role?) && @resource.has_role?(role)
  end

  private

  def admin?
    @resource.is_a?(Admin)
  end

  def citizen?
    has_role?(:citizen) || @resource.class.name.include?("Citizen")
  end

  def officer?
    has_role?(:officer) || @resource.class.name.include?("Officer")
  end

  def banking_agent?
    has_role?(:banking_agent)
  end

  def partner_admin?
    has_role?(:partner_admin)
  end
end
