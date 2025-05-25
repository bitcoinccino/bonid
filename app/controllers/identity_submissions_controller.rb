# app/controllers/identity_submissions_controller.rb
class IdentitySubmissionsController < ApplicationController
  helper IdentitySubmissionsHelper
  before_action :authenticate_user!, except: [:verify]
  before_action :redirect_admin!, only: [:new, :create, :edit, :update, :index]
  before_action :set_submission, only: [:show, :edit, :update, :request_reset]
  before_action :ensure_profile_complete!, only: [:new, :create]
  before_action :load_partner_from_session, only: [:index, :new]
  before_action :store_partner_in_session, only: [:new, :create]

  def new
    if session[:bonid_partner_id].blank?
      redirect_to partners_path, alert: "🚫 Please start from a verified partner page." and return
    end

    @partner = Partner.find_by(id: session[:bonid_partner_id])
    unless @partner&.verified_at?
      session.delete(:bonid_partner_id)
      redirect_to partners_path, alert: "🚫 This partner is not verified." and return
    end

    @identity_submission = current_user.identity_submissions.build(submission_type: "initial", partner: @partner)
    @identity_submission.build_address unless @identity_submission.address.present?
  end

  def index
    @submissions = current_user.identity_submissions.order(created_at: :desc)
    @last_submission = @submissions.find { |s| s.status != "revoked" } || @submissions.first
    @partner = Partner.find_by(id: session[:bonid_partner_id])
  end

  def show
    unless @submission
      redirect_to user_dashboard_path, alert: "Submission not found." and return
    end
    @submissions = current_user.identity_submissions.order(created_at: :desc)
    @last_submission = @submissions.first
  end

  def create
    @identity_submission = current_user.identity_submissions.build(identity_submission_params)
    @identity_submission.partner_id ||= session[:bonid_partner_id]

    if @identity_submission.partner_id.nil?
      redirect_to start_verification_path, alert: "Please start from a verified partner page." and return
    end

    @identity_submission.status = :pending
    @identity_submission.submission_type ||= "initial"

    if @identity_submission.save
      session.delete(:bonid_partner_id)
      redirect_to user_dashboard_path, notice: "Verification submitted successfully."
    else
      flash.now[:alert] = "There was a problem submitting your verification."
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @identity_submission = current_user.identity_submissions.find(params[:id])
  end

  def update
    @submission.status = :pending
    params[:identity_submission][:submission_type] = params[:identity_submission][:submission_type].to_s.downcase
    if @submission.update(identity_submission_params)
      redirect_to identity_submission_path(@submission), notice: "Your submission was updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def regenerate_combined_qr!
    raise "Missing verification token" if verification_token.blank?
  
    sig = user.send(:secure_bonid_signature)
    host = Rails.application.config.default_url_host
  
    full_url = Rails.application.routes.url_helpers.verify_identity_submission_url(
      verification_token,
      host: host,
      sig: sig,
      partner: partner&.slug
    )
  
    qr = RQRCode::QRCode.new(full_url)
  
    png = qr.as_png(
      bit_depth: 1,
      border_modules: 4,
      color_mode: :rgb,
      color: verified? ? '#00209F' : '#6B7280',
      fill: verified? ? '#FFFFFF' : '#D1D5DB',
      module_px_size: 6,
      size: 240
    )
  
    update_column(:qr_png_base64, Base64.strict_encode64(png.to_s))
  end
  


  def verify
    payload = nil
  
    # Try to parse raw JSON from the QR scan
    begin
      payload = JSON.parse(request.query_string.presence || request.raw_post.presence || params[:payload])
    rescue JSON::ParserError
      return redirect_to root_path, alert: "QR code is not valid."
    end
  
    token = payload["verification_token"]
    signature = payload["signature"]
    bonid = payload["bonid"]
    partner_slug = payload["partner"]
  
    @submission = IdentitySubmission.find_by(verification_token: token)
  
    unless @submission
      return redirect_to root_path, alert: "Invalid or expired BonID."
    end
  
    expected_sig = OpenSSL::HMAC.hexdigest(
      "SHA256",
      Rails.application.credentials.dig(:bonid, :signature_secret),
      @submission.user.bonid.to_s
    )
  
    unless ActiveSupport::SecurityUtils.secure_compare(signature.to_s, expected_sig.to_s)
      return redirect_to root_path, alert: "Signature verification failed."
    end
  
    # Log scan (if not recently scanned)
    unless recently_scanned?(@submission)
      QrScan.create!(
        identity_submission: @submission,
        scanned_at: Time.current,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        partner: Partner.find_by(slug: partner_slug),
        verified_by: "QR Scan"
      )
    end
  
    if @submission.verified?
      render :verified_profile
    else
      redirect_to root_path, alert: "This BonID is not verified or has expired."
    end
  end
  
  


  def has_verified_bonid?(user)
    user.identity_submissions.approved
        .where("expires_at > ?", Time.current)
        .exists?
  end

  def eligible_for_new_bonid_request?(user, submissions)
    return false unless user && profile_complete?(user)

    last_submission = submissions&.first
    return false if last_submission.nil?
    return false if last_submission.reset_request_status == "pending"
    return false if last_submission.submission_type == "reissue" && last_submission.status == "pending"

    last_submission.approved? ||
    last_submission.rejected? ||
    last_submission.status == "revoked" ||
    last_submission.reset_request_status.in?(%w[approved rejected]) ||
    (last_submission.expires_at.present? && last_submission.expires_at < Time.current) ||
    (last_submission.created_at < 6.months.ago)
  end

  def request_new
    reason = params[:reason]
    other_reason = params[:other_reason]

    if reason.blank?
      return redirect_to user_dashboard_path, alert: "Please provide a reason for your request."
    end

    previous = current_user.identity_submissions.approved.last
    previous&.update!(status: :revoked)

    current_user.identity_submissions.create!(
      status: :pending,
      submission_type: :reissue,
      reason: reason,
      other_reason: other_reason
    )

    redirect_to user_dashboard_path, notice: "Your new BonID request has been submitted."
  end

  def approve
    @submission = IdentitySubmission.find(params[:id])
    @submission.mark_as_verified!
    redirect_to admin_identity_submissions_path, notice: "Submission approved and BonID issued."
  end

  def request_reset
    if @submission.approved?
      reason = params[:reason]
      other_reason = params[:other_reason]

      if reason.blank?
        return redirect_to identity_submission_path(@submission), alert: "Please select a reason for your reset request."
      end

      @submission.update!(
        reset_requested: true,
        reset_requested_at: Time.current,
        reset_request_status: nil,
        status: :pending,
        reason: reason,
        other_reason: (reason == "other" ? other_reason : nil)
      )

      redirect_to identity_submission_path(@submission), notice: "Reset request sent! Admin will review it shortly."
    else
      redirect_to identity_submission_path(@submission), alert: "Only approved BonIDs can request a reset."
    end
  end

  private

  def identity_submission_params
    params.require(:identity_submission).permit(
      :id_type,
      :submission_type,
      :partner_id,
      :cin_front,
      :cin_back,
      :passport,
      :selfie,
      :proof_of_address,
      :digicel_phone_bill,
      :natcom_phone_bill,
      :baptismal_certificate,
      :birth_certificate,
      :adoption_certificate,
      :naturalization_monitor_copy,
      :archives_extract,
      :pnh_record,
      :bank_record,
      :western_union_record,
      :moneygram_record,
      :sendwave_record,
      :unitransfer_record,
      :taptap_record,
      :car_registration,
      :additional_proof,
      :additional_proof_type,
      :reason,
      :other_reason,
      :verification_token
    )
  end

  def set_submission
    @submission = current_user.identity_submissions.find_by(id: params[:id])
    redirect_to user_dashboard_path, alert: "Submission not found." unless @submission
  end

  def ensure_profile_complete!
    unless profile_complete?(current_user)
      redirect_to edit_profile_path, alert: "To submit your identity for verification, please complete your profile first."
    end
  end

  def recently_scanned?(submission)
    QrScan.where(identity_submission: submission)
          .where(ip_address: request.remote_ip)
          .where(user_agent: request.user_agent)
          .where("scanned_at >= ?", 10.minutes.ago)
          .exists?
  end

  def redirect_admin!
    if current_user&.admin?
      redirect_to root_path, alert: "Admins are not allowed to perform this action."
    end
  end

  def load_partner_from_session
    @partner = Partner.find_by(id: session[:bonid_partner_id]) if session[:bonid_partner_id].present?
  end

  def store_partner_in_session
    if params[:partner].present?
      partner = Partner.find_by(slug: params[:partner])
      session[:bonid_partner_id] = partner.id if partner&.verified_at?
    end
  end
end
