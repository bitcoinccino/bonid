module Admin
  class PartnerPolicy < BasePolicy
    def dashboard?; admin_only; end
    def index?; admin_only; end
    def show?; admin_only; end
    def edit?; admin_only; end
    def update?; admin_only; end
    def destroy?; admin_only; end

    # Only allow resend for pending partners
    def resend_verification_email?
      admin_only && (record.status.nil? || record.status == "pending")
    end

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
      define_method("#{action}?") { admin_only }
    end
  end
end
