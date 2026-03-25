# app/controllers/identity_submissions_controller.rb
class IdentitySubmissionsController < ApplicationController
  layout "public" # 👈 Lightweight layout for verified/public certificate views

  # Skip CSRF because external QR scans or API-like requests may hit these endpoints

  if respond_to?(:skip_before_action)

            if defined?(verify_authenticity_token) && respond_to?(:skip_before_action)
      skip_before_action :verify_authenticity_token, only: %i[verify verified_profile], raise: false
            end

  end


  before_action :set_submission_by_token, only: %i[verified_profile]
  before_action :authenticate_any_scope!, only: %i[verified_profile]
  before_action :authorize_access!, only: %i[verified_profile]

  # -----------------------------------------------------------------------------
  # 🔍 Public QR Verification
  # GET /identity_submissions/verify/:token
  # -----------------------------------------------------------------------------
  def verify
    token     = params[:verification_token] || params[:token]
    signature = params[:signature]
    partner   = Partner.find_by(slug: params[:partner]) if params[:partner].present?

    @submission = IdentitySubmission.approved.find_by(verification_token: token)

    unless @submission
      redirect_to root_path, alert: "Invalid or expired BonID." and return
    end

    # ✅ Optional: verify cryptographic HMAC authenticity
    if signature.present?
      expected = OpenSSL::HMAC.hexdigest(
        "SHA256",
        Rails.application.credentials.dig(:bonid, :signature_secret),
        @submission.user.bonid.to_s
      )

      unless ActiveSupport::SecurityUtils.secure_compare(signature, expected)
        redirect_to root_path, alert: "Signature verification failed." and return
      end
    end

    # ✅ Log scan (avoid duplicates within 30s)
    unless recently_scanned?(@submission)
      QrScanLogger.log!(
        submission: @submission,
        request: request,
        source: "public_scan",
        partner: partner
      )
    end

    redirect_to verified_profile_citizens_identity_submission_path(@submission.public_token, partner: params[:partner])
  end

  # -----------------------------------------------------------------------------
  # 📜 Verified Profile (Citizen Owner or Verified Partner Only)
  # GET /identity_submissions/:public_token/verified_profile
  # -----------------------------------------------------------------------------
  def verified_profile
    unless @submission&.status_approved? && @submission.expires_at&.future?
      redirect_to root_path, alert: "This BonID is not verified or has expired." and return
    end

    @partner = Partner.find_by(slug: params[:partner]) if params[:partner].present?

    # Choose certificate partial based on role / sector
    @certificate_partial =
      if citizen_signed_in? && current_citizen == @submission.user
        "identity_submissions/certificate_sections/full_details"
      elsif @partner&.sector == "banking"
        "identity_submissions/certificate_sections/banking"
      elsif @partner&.sector == "embassy"
        "identity_submissions/certificate_sections/embassy"
      elsif @partner&.sector == "law_enforcement"
        "identity_submissions/certificate_sections/law_enforcement"
      else
        "identity_submissions/certificate_sections/public"
      end
  end

  # -----------------------------------------------------------------------------
  # 🧩 Private Helpers
  # -----------------------------------------------------------------------------
  private

  # Securely find by non-enumerable public_token
  def set_submission_by_token
    @submission = IdentitySubmission.find_by!(public_token: params[:public_token])
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "Invalid BonID link."
  end

  # Allow access for citizen (owner) or verified partner only
  def authorize_access!
    # 1️⃣ Citizen owner
    return if citizen_signed_in? && current_citizen == @submission.user

    # 2️⃣ Verified partner
    if current_partner.present?
      return if current_partner.verified_at.present?
    end

    # 3️⃣ Otherwise deny
    redirect_to root_path,
                alert: "Access denied. Only the BonID owner or a verified partner may view this certificate."
  end

  # Allow signed-in citizen OR partner to proceed
  def authenticate_any_scope!
    unless citizen_signed_in? || current_partner.present?
      redirect_to root_path, alert: "You must be signed in to view this BonID."
    end
  end

  # Prevent redundant QR scan logs
  def recently_scanned?(submission)
    last_scan = submission.qr_scan_logs.order(created_at: :desc).first
    last_scan && last_scan.created_at > 30.seconds.ago
  end
end



# # app/controllers/identity_submissions_controller.rb
# class IdentitySubmissionsController < ApplicationController
#   layout "citizen"
#   helper IdentitySubmissionsHelper

#   # ✅ Public access allowed for QR verification + certificate
#   skip_before_action :verify_authenticity_token, only: %i[verify verified_profile], raise: false


#   before_action :redirect_admin!, only: [ :new, :create, :edit, :update, :index ]
#   before_action :set_submission, only: [ :show, :edit, :update, :request_reset ]
#   before_action :ensure_profile_complete!, only: [ :new, :create ]

#   # Enforce verified partner presence in session for critical actions
#   before_action :ensure_verified_partner_in_session, only: [ :index, :new, :create ]

#   before_action :load_partner_from_session, only: [ :index, :new ]
#   before_action :store_partner_in_session, only: [ :new, :create ]

#   # -------------------------
#   # CITIZEN DASHBOARD ACTIONS
#   # -------------------------
#   def index
#     @submissions = current_user.identity_submissions.order(created_at: :desc)
#     @last_submission = @submissions.find { |s| s.status != "revoked" } || @submissions.first
#     @partner = Partner.find_by(id: session[:bonid_partner_id])
#   end

#   def new
#     @partner = Partner.find_by(id: session[:bonid_partner_id])
#     unless @partner&.verified_at?
#       session.delete(:bonid_partner_id)
#       redirect_to partners_path, alert: "🚫 This partner is not verified." and return
#     end

#     existing = current_user.identity_submissions.where.not(status: %w[revoked expired]).first
#     if existing.present?
#       redirect_to identity_submission_path(existing),
#                   alert: "⚠️ You already submitted a BonID. Please wait for review or request a reset." and return
#     end

#     resolved_type = IdentitySubmission.assign_submission_type_for(current_user)
#     @identity_submission = current_user.identity_submissions.build(
#       submission_type: resolved_type,
#       partner: @partner
#     )
#   end

#   def create
#     existing = current_user.identity_submissions.where.not(status: %w[revoked expired]).first
#     if existing.present?
#       redirect_to identity_submission_path(existing),
#                   alert: "🚫 You already submitted a BonID. Please wait or request a reset." and return
#     end

#     @identity_submission = current_user.identity_submissions.build(identity_submission_params)
#     @identity_submission.partner_id ||= session[:bonid_partner_id]
#     @identity_submission.user = current_user
#     @identity_submission.status = :pending
#     @identity_submission.submission_type ||= "initial"

#     if @identity_submission.partner_id.nil?
#       redirect_to start_verification_path, alert: "🚫 Please start from a verified partner page." and return
#     end

#     begin
#       attach_signature!(@identity_submission)
#     rescue => e
#       Rails.logger.error "Failed to attach signature: #{e.message}"
#       flash.now[:alert] = "⚠️ Invalid or missing signature. Please upload or draw it again."
#       render :new, status: :unprocessable_entity and return
#     end

#     unless @identity_submission.signature.attached?
#       flash.now[:alert] = "✍️ Please provide a signature before submitting your BonID verification."
#       render :new, status: :unprocessable_entity and return
#     end

#     if @identity_submission.save
#       session.delete(:bonid_partner_id)

#       if current_user.citizen?
#         redirect_to citizens_dashboard_path,
#                     notice: "✅ Documents submitted successfully. Track your BonID status in your dashboard."
#       elsif current_user.officer?
#         redirect_to officers_dashboard_path,
#                     notice: "✅ Submission completed on behalf of Officer #{current_user.full_name}."
#       else
#         redirect_to user_dashboard_path,
#                     notice: "✅ Verification submitted successfully."
#       end
#     else
#       flash.now[:alert] = "⚠️ There was a problem submitting your verification."
#       render :new, status: :unprocessable_entity
#     end
#   end

#   def show
#     unless @submission
#       redirect_to user_dashboard_path, alert: "Submission not found." and return
#     end
#     @submissions = current_user.identity_submissions.order(created_at: :desc)
#     @last_submission = @submissions.first
#   end

#   def edit
#     @identity_submission = current_user.identity_submissions.find(params[:id])
#   end

#   def update
#     @submission.status = :pending
#     params[:identity_submission][:submission_type] =
#       params[:identity_submission][:submission_type].to_s.downcase

#     begin
#       attach_signature!(@submission)
#     rescue => e
#       Rails.logger.error "Failed to attach signature during update: #{e.message}"
#       flash.now[:alert] = "⚠️ Invalid signature. Please upload or draw it again."
#       render :edit, status: :unprocessable_entity and return
#     end

#     unless @submission.signature.attached?
#       flash.now[:alert] = "✍️ Signature is required before updating your BonID submission."
#       render :edit, status: :unprocessable_entity and return
#     end

#     if @submission.update(identity_submission_params)
#       if current_user.citizen?
#         redirect_to citizens_dashboard_path, notice: "✅ Your submission was updated successfully."
#       elsif current_user.officer?
#         redirect_to officers_dashboard_path, notice: "✅ Officer submission updated successfully."
#       else
#         redirect_to identity_submission_path(@submission), notice: "✅ Your submission was updated."
#       end
#     else
#       flash.now[:alert] = "⚠️ Failed to update submission."
#       render :edit, status: :unprocessable_entity
#     end
#   end

#   # -------------------------
#   # PUBLIC QR VERIFICATION FLOW
#   # -------------------------
#   def verify
#     token        = params[:verification_token]
#     signature    = nil
#     partner_slug = nil

#     # Parse JSON payload (if scanning app sends JSON)
#     if request.content_type == "application/json" || params[:payload].present?
#       begin
#         payload      = JSON.parse(request.query_string.presence || request.raw_post.presence || params[:payload])
#         token        = payload["verification_token"] || token
#         signature    = payload["signature"]
#         partner_slug = payload["partner"]
#       rescue JSON::ParserError
#         return redirect_to root_path, alert: "QR code is not valid."
#       end
#     end

#     @submission = IdentitySubmission.approved.find_by(verification_token: token)
#     unless @submission
#       return redirect_to root_path, alert: "Invalid or expired BonID."
#     end

#     # Optional HMAC check
#     if signature.present?
#       expected_sig = OpenSSL::HMAC.hexdigest(
#         "SHA256",
#         Rails.application.credentials.dig(:bonid, :signature_secret),
#         @submission.user.bonid.to_s
#       )

#       unless ActiveSupport::SecurityUtils.secure_compare(signature.to_s, expected_sig.to_s)
#         return redirect_to root_path, alert: "Signature verification failed."
#       end
#     end

#     partner = Partner.find_by(slug: partner_slug)

#     # ✅ Always log scan (even without signature)
#     unless recently_scanned?(@submission)
#       QrScanLogger.log!(
#         submission: @submission,
#         request: request,
#         source: "public_scan",
#         partner: partner
#       )
#     end

#     # Redirect to public verified profile
#     redirect_to verified_profile_identity_submission_path(@submission)
#   end

#   def verified_profile
#     @submission = IdentitySubmission.find(params[:id])
#     unless @submission&.status_approved?
#       redirect_to root_path, alert: "This BonID is not verified or has expired." and return
#     end

#     render :verified_profile, layout: "public"
#   end

#   def verified_profile
#     @submission = IdentitySubmission.find(params[:id])
#     unless @submission&.status_approved?
#       redirect_to root_path, alert: "This BonID is not verified or has expired." and return
#     end

#     @partner = Partner.find_by(slug: params[:partner]) if params[:partner].present?

#     # Pick which partial to render inside the certificate
#     @certificate_partial =
#       if citizen_signed_in? && current_citizen == @submission.user
#         "identity_submissions/certificate_sections/full_details"
#       elsif @partner&.sector == "banking"
#         "identity_submissions/certificate_sections/banking"
#       elsif @partner&.sector == "embassy"
#         "identity_submissions/certificate_sections/embassy"
#       elsif @partner&.sector == "law_enforcement"
#         "identity_submissions/certificate_sections/law_enforcement"
#       else
#         "identity_submissions/certificate_sections/public"
#       end

#     render :verified_profile, layout: "public"
#   end

#   # -------------------------
#   # OTHER ACTIONS
#   # -------------------------
#   def request_new
#     previous = current_user.identity_submissions.where(status: [ :approved, :revoked, :expired ])
#                                                 .order(verified_at: :desc).first

#     if previous.nil? && session[:bonid_partner_id].blank?
#       return redirect_to user_dashboard_path, alert: "You must sign up through a verified partner."
#     end

#     partner_id = previous&.partner_id || session[:bonid_partner_id]
#     unless partner_id.present?
#       return redirect_to user_dashboard_path, alert: "Missing partner information. Please contact support."
#     end

#     previous&.update!(status: :revoked)

#     submission = current_user.identity_submissions.new(
#       status: :pending,
#       submission_type: :reissue,
#       reason: params[:reason],
#       other_reason: params[:other_reason],
#       id_type: current_user.id_type.presence || "cin",
#       partner_id: partner_id,
#       skip_document_validations: true
#     )

#     if submission.save
#       redirect_to user_dashboard_path, notice: "Your new BonID request has been submitted."
#     else
#       redirect_to user_dashboard_path, alert: submission.errors.full_messages.to_sentence
#     end
#   end

#   def refresh_qr
#     @submission = current_user.identity_submissions.approved.last
#     if @submission.present?
#       @submission.regenerate_combined_qr!
#       redirect_to user_dashboard_path, notice: "QR code refreshed."
#     else
#       redirect_to dashboard_path, alert: "No valid BonID found."
#     end
#   end

#   def scan_history
#     @submissions = current_user.identity_submissions.includes(:qr_scan_logs)
#   end

#   def support_faq
#     # Render FAQ partial
#   end

#   private

#   def attach_signature!(submission)
#     if params[:identity_submission][:signature_drawn].present?
#       data = params[:identity_submission][:signature_drawn]
#       content = Base64.decode64(data.split(",")[1])
#       io = StringIO.new(content)
#       submission.signature.attach(io: io, filename: "signature.png", content_type: "image/png")
#     elsif params[:identity_submission][:signature].present?
#       # Rails auto-attaches
#     end

#     if submission.signature.attached? && !submission.signature.image?
#       submission.signature.purge
#       raise "Attached file is not a valid image."
#     end
#   end

#   def identity_submission_params
#     params.require(:identity_submission).permit(
#       :id_type, :submission_type, :partner_id, :cin_front, :cin_back, :passport, :selfie,
#       :proof_of_address, :digicel_phone_bill, :natcom_phone_bill, :baptismal_certificate,
#       :birth_certificate, :adoption_certificate, :naturalization_monitor_copy, :archives_extract,
#       :pnh_record, :bank_record, :western_union_record, :moneygram_record, :sendwave_record,
#       :unitransfer_record, :taptap_record, :car_registration, :additional_proof, :additional_proof_type,
#       :reason, :other_reason, :verification_token, :signature
#     )
#   end

#   def set_submission
#     @submission = current_user.identity_submissions.find_by(id: params[:id])
#     redirect_to user_dashboard_path, alert: "Submission not found." unless @submission
#   end

#   def ensure_profile_complete!
#     unless profile_complete?(current_user)
#       redirect_to edit_profile_path,
#                   alert: "To submit your identity for verification, please complete your profile first."
#     end
#   end

#   def ensure_verified_partner_in_session
#     partner_id = session[:bonid_partner_id]
#     unless partner_id.present? && Partner.where(id: partner_id).where.not(verified_at: nil).exists?
#       redirect_to partners_path, alert: "🚫 Please start from a verified partner page." and return
#     end
#   end

#   def redirect_admin!
#     redirect_to root_path, alert: "Admins are not allowed to perform this action." if current_user&.admin?
#   end

#   def load_partner_from_session
#     @partner = Partner.find_by(id: session[:bonid_partner_id]) if session[:bonid_partner_id].present?
#   end

#   def store_partner_in_session
#     return unless params[:partner].present?
#     partner = Partner.find_by(slug: params[:partner])
#     if partner&.verified_at?
#       session[:bonid_partner_id] = partner.id
#     else
#       redirect_to partners_path, alert: "🚫 This partner is not verified." and return
#     end
#   end

#   def recently_scanned?(submission)
#     last_scan = submission.qr_scan_logs.order(created_at: :desc).first
#     last_scan && last_scan.created_at > 30.seconds.ago
#   end
# end
