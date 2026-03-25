puts "Loading AccessControl module at #{Time.now}"

module AccessControl
  # ===========================================================================
  # ALLOWED NAMESPACE ACCESS PER ROLE
  # Each role is mapped to the root-level path namespaces it should access.
  # ===========================================================================
  ROLE_NAMESPACE_ACCESS = {
    citizen: [
      "/",
      "/citizens",
      "/citizens/dashboard",
      "/citizens/profile",
      "/citizens/identity_submissions",
      "/verify"
    ],

    officer: [
      "/",
      "/officers",
      "/officers/dashboard",
      "/officers/incident_reports",
      "/officers/scan",
      "/verify"
    ],

    partner_admin: [
      "/",
      "/partner_portal",
      "/partner_portal/dashboard",
      "/partner_portal/records",
      "/partner_portal/settings",
      "/verify"
    ],

    reviewer: [
      "/",
      "/admin/identity_submissions",
      "/admin/dashboard",
      "/verify"
    ],

    admin: [
      "/",
      "/admin",
      "/admin/dashboard",
      "/admin/partners",
      "/admin/identity_submissions",
      "/verify"
    ]
  }.freeze

  # ===========================================================================
  # Match an incoming path to allowed access
  # ===========================================================================
  def self.allowed?(user, path)
    return false unless user

    # Determine user role
    role = user.roles.first&.name&.to_sym
    return false unless ROLE_NAMESPACE_ACCESS.key?(role)

    # Check if path matches any allowed namespace
    ROLE_NAMESPACE_ACCESS[role].any? do |allowed|
      path.start_with?(allowed)
    end
  end
end
