# app/controllers/officers_controller.rb
require 'openssl'
require 'json'

class OfficersController < ApplicationController
  before_action :authenticate_officer!, only: [
    :dashboard,
    :edit,
    :update,
    :new_incident_report,
    :create_incident_report
  ]

  # === Dashboard ===
  def dashboard
    @officer = current_officer
    @partner = @officer.partner
    @incident_reports = @officer.incident_reports.order(created_at: :desc)
  end

  # === New Incident Report ===
  def new_incident_report
    @incident_report = current_officer.incident_reports.build
    @incident_report.build_address unless @incident_report.address

    if params[:bonid].present?
      @incident_report.suspect_bonid = params[:bonid]
      suspect = User.find_by(bonid: params[:bonid])

      if suspect && suspect.identity_submissions.approved.where("expires_at > ?", Time.current).exists?
        @incident_report.suspect_name = suspect.full_name
        @incident_report.suspect_user_id = suspect.id
      else
        flash.now[:alert] = "⚠️ No verified user found for this BonID."
      end
    end
  end

  # === Create Incident Report ===
  def create_incident_report
    @incident_report = current_officer.incident_reports.build(incident_report_params)

    if @incident_report.save
      redirect_to officer_dashboard_path, notice: "Incident report submitted successfully."
    else
      flash.now[:alert] = "Please fix the errors below."
      render :new_incident_report, status: :unprocessable_entity
    end
  end

  # === Officer Profile ===
  def edit
    @officer = current_officer
    @unit_options = Officer.unit_options
  end

  def update
    @officer = current_officer

    if @officer.update(officer_params)
      redirect_to officer_dashboard_path, notice: "Profile updated successfully."
    else
      flash.now[:alert] = "Please fix the errors below."
      render :edit, status: :unprocessable_entity
    end
  end

  # === Accept Invitation ===
  def accept_invitation
    @officer = Officer.find_by(invitation_token: params[:token])

    unless @officer&.invited?
      redirect_to root_path, alert: "🚫 This invitation is invalid or has already been used." and return
    end

    if request.put?
      if @officer.update(officer_invitation_params.merge(
        status: :active,
        invitation_accepted_at: Time.current
      ))
        sign_in(:officer, @officer)
        flash[:notice] = "✅ Welcome, #{@officer.full_name.split.first}! Please complete your profile."
        redirect_to edit_officer_profile_path
      else
        flash.now[:alert] = "⚠️ Please correct the errors and try again."
        render :accept_invitation, status: :unprocessable_entity
      end
    end
  end

  # === Direct QR Scan (Camera or Link) ===
  def scan_bonid
    bonid_part, sig = params[:payload].to_s.strip.split("|")
    key = Rails.application.credentials.dig(:bonid, :signature_secret)

    expected_sig = OpenSSL::HMAC.hexdigest("SHA256", key, bonid_part)

    unless sig.present? && ActiveSupport::SecurityUtils.secure_compare(sig, expected_sig)
      redirect_to root_path, alert: "Invalid or tampered BonID QR code." and return
    end

    user = User.find_by(bonid: bonid_part)
    unless user
      redirect_to root_path, alert: "BonID not found." and return
    end

    redirect_to new_officer_incident_report_path(bonid: user.bonid)
  end


  # app/controllers/officers_controller.rb
def scan_qrcode
  begin
    payload = JSON.parse(params[:qr_data]) # expects { bonid: "...", signature: "..." }
    bonid = payload["bonid"]
    signature = payload["signature"]

    # Validate presence
    if bonid.blank? || signature.blank?
      return render json: { error: "Missing BonID or signature." }, status: :unprocessable_entity
    end

    # Regenerate signature and compare
    expected_signature = OpenSSL::HMAC.hexdigest(
      "SHA256",
      Rails.application.credentials.dig(:bonid, :signature_secret),
      bonid
    )

    unless ActiveSupport::SecurityUtils.secure_compare(signature, expected_signature)
      return render json: { error: "Invalid or tampered BonID QR code" }, status: :unauthorized
    end

    # Confirm verified user exists
    user = User.find_by(bonid: bonid)
    unless user && user.identity_submissions.approved.where("expires_at > ?", Time.current).exists?
      return render json: { error: "No verified user found for this BonID" }, status: :not_found
    end

    render json: { name: user.full_name, bonid: user.bonid }, status: :ok

  rescue JSON::ParserError
    render json: { error: "Malformed QR code" }, status: :bad_request
  end
end


  # === Private Helpers ===
  private

  def verify_bonid_payload(payload)
    bonid, provided_signature = payload.to_s.strip.split("|")
    return nil if bonid.blank? || provided_signature.blank?

    key = Rails.application.credentials.dig(:bonid, :signature_secret)
    expected_signature = OpenSSL::HMAC.hexdigest("SHA256", key, bonid)

    return User.find_by(bonid: bonid) if ActiveSupport::SecurityUtils.secure_compare(provided_signature, expected_signature)

    nil
  end

  def officer_params
    params.require(:officer).permit(
      :full_name,
      :badge_id,
      :email,
      :phone_number,
      :rank,
      :unit_name,
      :unit_type
    )
  end

  def officer_invitation_params
    params.require(:officer).permit(
      :full_name,
      :badge_id,
      :password,
      :password_confirmation
    )
  end

  def incident_report_params
    params.require(:incident_report).permit(
      :crime_type,
      :description,
      :occurred_at,
      :suspect_bonid,
      :suspect_name,
      :suspect_user_id,
      :suspect_status,
      media: [],
      address_attributes: [
        :street_address,
        :postal_code,
        :commune_id,
        :communal_section_id,
        :arrondissement_id,
        :department_id,
        :locality,
        :latitude,
        :longitude
      ]
    )
  end
end
