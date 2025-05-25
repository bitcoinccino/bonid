# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  # === Before Actions ===
  before_action :store_partner_slug         # Stores partner slug from params
  before_action :store_partner_in_session   # Sets session[:bonid_partner_id] only if partner is verified
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :set_turbo_frame_request_variant
  before_action :store_partner_in_session

  # before_action :authenticate_user!

   # Redirect to root path after logout
   def after_sign_out_path_for(_resource_or_scope)
    root_path
   end

  # === Devise Overrides ===
  def require_officer!
    unless current_user&.officer?
      redirect_to root_path, alert: "Access restricted to PNH officers only."
    end
  end

  def after_sign_up_path_for(resource)
    after_sign_in_path_for(resource)
  end

  def after_sign_in_path_for(resource)
    if resource.admin?
      session[:admin_guidelines_confirmed] ? admin_identity_submissions_path : admin_guidelines_path
    elsif resource.reviewer?
      reviewer_dashboard_path
    elsif resource.identity_submissions.none?
      new_identity_submission_path # ✅ Redirect to new submission if none exist
    elsif profile_complete?(resource)
      user_dashboard_path
    else
      edit_profile_path
    end
  end
  

  helper_method :current_user
  # === Profile Completeness Check ===
  helper_method :profile_complete?

  def profile_complete?(user)
    user.first_name.present? &&
    user.last_name.present? &&
    user.sex.present? &&
    user.dob.present? &&
    user.id_type.present? &&
    user.id_number.present?
  end

  # === Devise Parameter Whitelisting ===
  def configure_permitted_parameters
    added_attrs = [
      :first_name, :middle_name, :last_name, :sex, :dob, :phone, :email,
      :password, :password_confirmation, :marital_status, :social_handle,
      :street_address, :postal_code, :locality, :country, :id_type,
      :id_number, :place_of_birth, :nationality, :id_issued_on,
      :id_expires_on, :issuing_authority, :terms
    ]

    devise_parameter_sanitizer.permit(:sign_up, keys: added_attrs)
    devise_parameter_sanitizer.permit(:account_update, keys: added_attrs)
  end

  # === Partner Session Tracking ===
  def store_partner_in_session
    if params[:partner].is_a?(String)
      partner = Partner.find_by(slug: params[:partner])
      if partner&.verified_at.present?
        session[:bonid_partner_id] = partner.id
        Rails.logger.info "🔐 Partner session set: #{partner.name} (ID: #{partner.id})"
      else
        Rails.logger.warn "🔍 Invalid or unverified partner slug: #{params[:partner]}"
        session.delete(:bonid_partner_id)
        flash[:alert] = "The partner link is invalid or not verified."
        redirect_to root_path and return
      end
    else
      session.delete(:bonid_partner_id)
      Rails.logger.debug "🌱 Organic signup or admin flow — no valid slug param"
    end
  end
  
  
  
  
  def store_partner_slug
    session[:partner_slug] = params[:partner] if params[:partner].present?
  end

  # === Turbo Frame Request ===
  def set_turbo_frame_request_variant
    request.variant = :turbo_frame if turbo_frame_request?
  end

  def after_sign_in_path_for(resource)
    if resource.is_a?(Officer)
      officer_dashboard_path
    else
      super
    end
  end

  helper_method :current_officer
end
