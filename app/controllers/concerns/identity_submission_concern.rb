# app/controllers/concerns/identity_submission_concern.rb
# frozen_string_literal: true

module IdentitySubmissionConcern
  extend ActiveSupport::Concern

  included do
    helper IdentitySubmissionsHelper

    # -----------------------------------------------------------------
    # Guards
    # -----------------------------------------------------------------
    before_action :redirect_admin!, only: %i[new create edit update index]
    before_action :set_submission, only: %i[show edit update request_reset]
    before_action :ensure_profile_complete!, only: %i[new create]

    # ✅ Run partner checks only if a partner session or param exists
    before_action :ensure_verified_partner_in_session, only: %i[new create], if: -> {
      session[:bonid_partner_id].present? || params[:partner].present?
    }

    before_action :load_partner_from_session, only: %i[index new]
    before_action :store_partner_in_session, only: %i[new create]
  end

  private

  # -----------------------------------------------------------------
  # Signature upload helper
  # -----------------------------------------------------------------
  def attach_signature!(submission)
    if params[:identity_submission][:signature_drawn].present?
      data = params[:identity_submission][:signature_drawn]
      content = Base64.decode64(data.split(",")[1])
      io = StringIO.new(content)
      submission.signature.attach(
        io: io,
        filename: "signature.png",
        content_type: "image/png"
      )
    end

    if submission.signature.attached? && !submission.signature.image?
      submission.signature.purge
      raise "Attached file is not a valid image."
    end
  end

  # -----------------------------------------------------------------
  # Submission loading / guards
  # -----------------------------------------------------------------
  def set_submission
    @submission = current_citizen.identity_submissions.find_by(id: params[:id])
    redirect_to citizens_identity_submissions_path,
                alert: "Submission not found." unless @submission
  end

  # ✅ Only require profile if citizen has no approved BonID yet
  def ensure_profile_complete!
    return if current_citizen.identity_submissions.approved.exists?
    unless current_citizen&.profile_complete?
      redirect_to edit_citizens_profile_path,
                  alert: "To submit your identity for verification, please complete your profile first."
    end
  end

  # -----------------------------------------------------------------
  # Partner verification (runs only in partner flow)
  # -----------------------------------------------------------------
  def ensure_verified_partner_in_session
    partner_id = session[:bonid_partner_id]
    partner = Partner.find_by(id: partner_id)

    unless partner&.verified_at?
      redirect_to partners_path,
                  alert: "🚫 Please start from a verified partner page." and return
    end
  end

  # -----------------------------------------------------------------
  # Partner context management
  # -----------------------------------------------------------------
  def load_partner_from_session
    @partner = Partner.find_by(id: session[:bonid_partner_id]) if session[:bonid_partner_id].present?
  end

  def store_partner_in_session
    return unless params[:partner].present?

    partner = Partner.find_by(slug: params[:partner])
    if partner&.verified_at?
      session[:bonid_partner_id] = partner.id
    else
      redirect_to partners_path, alert: "🚫 This partner is not verified." and return
    end
  end

  # -----------------------------------------------------------------
  # Misc
  # -----------------------------------------------------------------
  def redirect_admin!
    redirect_to root_path,
                alert: "Admins are not allowed to perform this action." if current_citizen&.admin?
  end

  def recently_scanned?(submission)
    last_scan = submission.qr_scan_logs.order(created_at: :desc).first
    last_scan && last_scan.created_at > 30.seconds.ago
  end
end
