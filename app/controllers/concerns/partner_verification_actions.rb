module PartnerVerificationActions
  extend ActiveSupport::Concern

  included do
    before_action :set_record, only: :verify
  end

  def verify
    if @record.status_pending?
      @record.update!(
        status: "verified",
        verified_at: Time.current,
        verifier_id: current_partner.id,
        verifier_type: current_partner.class.name,
        verifier_signature: generate_signature(@record)
      )
      create_audit_entry(@record, "verified", current_partner)
      UserMailer.bonid_approved(@record.user, @record).deliver_later
      redirect_to [ :partner_portal, sector_name, :dashboard, @record ],
                  notice: "✅ Record verified successfully."
    else
      redirect_back fallback_location: [ :partner_portal, sector_name, :dashboard, @record ],
                    alert: "⚠️ Record cannot be verified."
    end
  end
end
