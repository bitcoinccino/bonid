module PartnerPortal
  class PartnerPolicy < ApplicationPolicy
    # Partner admins can only see/manage their own partner
    def dashboard?
      user.partner_admin? && user.partner_id == record.id
    end

    # Partner admins cannot list all partners
    def index? = false

    def show?    = dashboard?
    def edit?    = dashboard?
    def update?  = dashboard?
    def destroy? = false
    def resend_verification_email? = false

    # Partner admins can invite/manage only under their own partner
    %w[
      invite_options
      invite_single
      send_invite_single
      invite_bulk
      send_invite_bulk
      manage_officers
      manage_assignments
      manage_incident_reports
    ].each do |action|
      define_method("#{action}?") { dashboard? }
    end

    # Optional redirect when unauthorized
    def resolve
      if user.partner_admin?
        { redirect_to: Rails.application.routes.url_helpers.partner_portal_root_path }
      else
        super
      end
    end
  end
end
