# frozen_string_literal: true

class ApplicationController < ActionController::Base
  helper CountryHelper
  include Pundit::Authorization

  protect_from_forgery with: :exception, prepend: true

  # ============================================================
  # 🌍 GLOBAL LOCALE (MUST BE EARLY)
  # Priority:
  # 1. ?lang= param
  # 2. session[:lang] (persisted choice)
  # 3. Browser Accept-Language
  # 4. Default locale
  # ============================================================
  before_action :set_locale

  # Keep lang param on all generated URLs (link_to, redirects, etc.)
  def default_url_options
    super.merge(lang: I18n.locale)
  end

  # ============================================================
  # GLOBAL BEFORE ACTIONS
  # ============================================================
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :set_turbo_frame_request_variant
  before_action :redirect_admin_from_user_dashboard, if: -> { current_user.present? rescue false }
  before_action :block_user_on_officer_routes
  before_action :require_password_confirmation, if: :sensitive_area?
  before_action :store_partner_context
  before_action :enforce_namespace_access
  before_action :ensure_active_account!
  before_action :set_partner_from_slug

  helper_method :profile_complete?, :current_role, :current_resource

  # ============================================================
  # 🌍 LOCALE HANDLER (SINGLE SOURCE OF TRUTH)
  # ============================================================
  protected

  def set_locale
    requested =
      params[:lang].presence ||
      session[:lang].presence ||
      request.env["HTTP_ACCEPT_LANGUAGE"]&.scan(/^[a-z]{2}/)&.first ||
      I18n.default_locale

    requested = requested.to_s.downcase
    allowed   = I18n.available_locales.map(&:to_s)
    chosen    = allowed.include?(requested) ? requested : I18n.default_locale.to_s

    I18n.locale    = chosen
    session[:lang] = chosen
  end

  def default_url_options
    { lang: I18n.locale }
  end

  # ============================================================
  # DEVise Mapping (Multi-scope)
  # ============================================================
  def devise_mapping
    controller = params[:controller].to_s

    case controller
    when /\Acitizens\//
      Devise.mappings[:citizen]
    when /\Aofficers\//
      Devise.mappings[:officer]
    when /\Apartner_portal\/partner_admin/
      Devise.mappings[:partner_admin]
    else
      super
    end
  end

  # ============================================================
  # CURRENT RESOURCE / ROLE
  # ============================================================
  def current_resource
    return current_admin_user if respond_to?(:current_admin_user) && current_admin_user
    return current_officer    if respond_to?(:current_officer) && current_officer
    return current_citizen    if respond_to?(:current_citizen) && current_citizen
    return current_user       if respond_to?(:current_user) && current_user
    nil
  end

  def current_role
    resource = current_resource
    return nil unless resource

    case resource
    when AdminUser
      :admin
    when Officer
      :officer
    else
      return :partner_admin if resource.has_role?(:partner_admin)
      return :citizen       if resource.has_role?(:citizen)
      return :reviewer      if resource.has_role?(:reviewer)
    end

    nil
  end

  # ============================================================
  # NAMESPACE ACCESS CONTROL
  # ============================================================
  def enforce_namespace_access
    role = current_role
    return unless role
    return if role == :admin
    return if request.path == "/"

    allowed_paths = ::AccessControl::ROLE_NAMESPACE_ACCESS[role] || []

    unless allowed_paths.any? { |prefix| request.path.start_with?(prefix) }
      Rails.logger.warn "[ACCESS BLOCKED] role=#{role} id=#{current_resource&.id} path=#{request.path}"
      redirect_to RoleRedirectService.redirect_path_for(current_resource),
                  alert: t("errors.unauthorized", default: "🚫 Access denied.")
    end
  end

  # ============================================================
  # DEVISE REDIRECTS
  # ============================================================
  def after_sign_in_path_for(resource_or_scope)
    resource = resource_or_scope.is_a?(Symbol) ? current_resource : resource_or_scope

    # If there is a pending OAuth consent session, resume it instead of going to dashboard.
    # This handles the OTP sign-in → consent flow for citizens signing in via a partner.
    if resource.is_a?(User) && resource.has_role?(:citizen)
      pending = session[:pending_consent]
      if pending.blank? && cookies.encrypted[:pending_consent].present?
        pending = JSON.parse(cookies.encrypted[:pending_consent]) rescue nil
      end
      if pending.present?
        partner_slug = pending.is_a?(Hash) ? (pending["partner_slug"] || pending[:partner_slug]) : nil
        return consent_oauth_index_path(partner_slug: partner_slug) if partner_slug.present?
      end
    end

    RoleRedirectService.after_sign_in_path_for(resource) ||
      stored_location_for(resource) ||
      root_path
  end

  def after_sign_out_path_for(resource_or_scope)
    RoleRedirectService.after_sign_out_path_for(resource_or_scope)
  end

  # ============================================================
  # AUTH / PUNDIT
  # ============================================================
  def require_no_authentication
    if current_resource
      redirect_to RoleRedirectService.redirect_path_for(current_resource)
    else
      super
    end
  end

  def pundit_user
    current_resource
  end

  # ============================================================
  # PROFILE / FORMS
  # ============================================================
  def profile_complete?(user)
    UserProfilePolicy.new(user).complete?
  end

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(
      :sign_up,
      keys: %i[email password password_confirmation terms]
    )

    devise_parameter_sanitizer.permit(
      :account_update,
      keys: UserProfilePolicy.permitted_params
    )
  end

  # ============================================================
  # TURBO / SECURITY
  # ============================================================
  def set_turbo_frame_request_variant
    request.variant = :turbo_frame if turbo_frame_request?
  end

  def sensitive_area?
    !devise_controller? && controller_name.in?(%w[settings payments critical_actions])
  end

  # ============================================================
  # OFFICER SECURITY
  # ============================================================
  def require_password_confirmation
    return unless current_role == :officer

    unless OfficerPasswordPolicy.new(current_resource).recently_confirmed?
      store_location_for(:officer, request.fullpath)
      redirect_to new_officer_password_confirmation_path
    end
  end

  # ============================================================
  # CROSS-ROLE BLOCKING
  # ============================================================
  def block_user_on_officer_routes
    if request.path.start_with?("/officers") && current_role == :citizen
      sign_out current_resource
      redirect_to root_path,
                  alert: "🚫 Access restricted to verified officers."
    end
  end

  def redirect_admin_from_user_dashboard
    if current_role == :admin && request.path == user_dashboard_path
      redirect_to admin_identity_submissions_path
    end
  end

  # ============================================================
  # PARTNER CONTEXT
  # ============================================================
  def store_partner_context
    PartnerSessionService.new(session, params).store!
  end

  def set_partner_from_slug
    return unless params[:partner_slug].present?

    @partner = Partner.find_by(slug: params[:partner_slug])
    if @partner
      session[:login_source] = "partner:#{@partner.slug}"
    end
  end

  # ============================================================
  # ACCOUNT ENFORCEMENT
  # ============================================================
  def ensure_active_account!
    return unless current_role == :partner_admin
    return unless current_resource.respond_to?(:active?)
    return if current_resource.active?

    sign_out(current_resource)
    redirect_to new_partner_admin_session_path,
                alert: "🚫 Your BonID access has been suspended."
  end
end


# # frozen_string_literal: true

# class ApplicationController < ActionController::Base
#   helper CountryHelper
#   include Pundit::Authorization

#   protect_from_forgery with: :exception, prepend: true

#   if respond_to?(:skip_before_action)
#     if defined?(verify_authenticity_token) && respond_to?(:skip_before_action)
#       skip_before_action :verify_authenticity_token, raise: false
#     end
#   end

#   allow_browser versions: :modern

#   # === Global Before Actions ===============================================
#   before_action :configure_permitted_parameters, if: :devise_controller?
#   before_action :set_turbo_frame_request_variant
#   before_action :redirect_admin_from_user_dashboard, if: -> { current_user.present? rescue false }
#   before_action :block_user_on_officer_routes
#   before_action :require_password_confirmation, if: :sensitive_area?
#   before_action :store_partner_context
#   before_action :enforce_namespace_access
#   before_action :ensure_active_account!
#   before_action :set_partner_from_slug

#   helper_method :profile_complete?, :current_role, :current_resource

#   # -------------------------------------------------------------------------
#   # === Correct Devise Mapping for Multi-Scope Setup
#   # -------------------------------------------------------------------------
#   def devise_mapping
#     controller = params[:controller].to_s
#     case controller
#     when /\Acitizens\//
#       Devise.mappings[:citizen]
#     when /\Aofficers\//
#       Devise.mappings[:officer]
#     when /\Apartner_portal\/partner_admin/
#       Devise.mappings[:partner_admin]
#     when /\Apartner_portal\/banking_agent/
#       Devise.mappings[:banking_agent]
#     else
#       super
#     end
#   end

#   # -------------------------------------------------------------------------
#   # === Unified Resource / Role Helpers
#   # -------------------------------------------------------------------------
#   def current_resource
#     return current_admin_user if respond_to?(:current_admin_user) && current_admin_user
#     return current_officer    if respond_to?(:current_officer) && current_officer
#     return current_user       if respond_to?(:current_user) && current_user
#     nil
#   end

#   def current_role
#     resource = current_resource
#     return nil unless resource

#     case resource
#     when AdminUser then :admin
#     when Officer   then :officer
#     else
#       if resource.respond_to?(:has_role?)
#         return :partner_admin if resource.has_role?(:partner_admin)
#         return :banker        if resource.has_role?(:banker)
#         return :banking_agent if resource.has_role?(:banking_agent)
#         return :citizen       if resource.has_role?(:citizen)
#         return :reviewer      if resource.has_role?(:reviewer)
#       end
#       nil
#     end
#   end

#   # -------------------------------------------------------------------------
#   # === Namespace Access Enforcement
#   # -------------------------------------------------------------------------
#   def enforce_namespace_access
#     role = current_role
#     return unless role
#     return if role == :admin
#     return if request.path == "/"

#     allowed_paths = ::AccessControl::ROLE_NAMESPACE_ACCESS[role] || []
#     unless allowed_paths.any? { |prefix| request.path.start_with?(prefix) }
#       Rails.logger.warn "[ACCESS BLOCKED] role=#{role} id=#{current_resource&.id} tried to access #{request.path}"
#       redirect_to RoleRedirectService.redirect_path_for(current_resource),
#                   alert: "🚫 Access denied for your role."
#     end
#   end

#   # -------------------------------------------------------------------------
#   # === Devise Redirect Hooks (via RoleRedirectService)
#   # -------------------------------------------------------------------------
#   def after_sign_in_path_for(resource_or_scope)
#     resource = resource_or_scope.is_a?(Symbol) ? current_resource : resource_or_scope
#     RoleRedirectService.after_sign_in_path_for(resource) ||
#       stored_location_for(resource) ||
#       root_path
#   end

#   def after_sign_out_path_for(resource_or_scope)
#     RoleRedirectService.after_sign_out_path_for(resource_or_scope)
#   end

#   # -------------------------------------------------------------------------
#   # === Auth Reentry & Pundit Integration
#   # -------------------------------------------------------------------------
#   protected

#   def require_no_authentication
#     if current_resource
#       Rails.logger.info "[AUTH CHECK] Already signed in as #{current_role}, redirecting…"
#       redirect_to RoleRedirectService.redirect_path_for(current_resource)
#     else
#       super
#     end
#   end

#   def pundit_user
#     current_resource
#   end

#   # -------------------------------------------------------------------------
#   # === Form & Profile Helpers
#   # -------------------------------------------------------------------------
#   def profile_complete?(user)
#     UserProfilePolicy.new(user).complete?
#   end

#   def configure_permitted_parameters
#     devise_parameter_sanitizer.permit(:sign_up,        keys: %i[email password password_confirmation terms])
#     devise_parameter_sanitizer.permit(:account_update, keys: UserProfilePolicy.permitted_params)
#   end

#   # -------------------------------------------------------------------------
#   # === Turbo / Security Utilities
#   # -------------------------------------------------------------------------
#   def set_turbo_frame_request_variant
#     request.variant = :turbo_frame if turbo_frame_request?
#   end

#   def sensitive_area?
#     !devise_controller? && controller_name.in?(%w[settings payments critical_actions])
#   end

#   # -------------------------------------------------------------------------
#   # === Officer-specific Security Flow
#   # -------------------------------------------------------------------------
#   def require_password_confirmation
#     return unless current_role == :officer
#     unless OfficerPasswordPolicy.new(current_resource).recently_confirmed?
#       store_location_for(:officer, request.fullpath)
#       redirect_to new_officer_password_confirmation_path
#     end
#   end

#   # -------------------------------------------------------------------------
#   # === Cross-role Restrictions
#   # -------------------------------------------------------------------------
#   def block_user_on_officer_routes
#     if request.path.start_with?("/officers") && current_role == :citizen
#       sign_out current_resource
#       redirect_to root_path,
#                   alert: "🚫 Access restricted to verified officers of the Haitian National Police (PNH)."
#     end
#   end

#   def redirect_admin_from_user_dashboard
#     if current_role == :admin && request.path == user_dashboard_path
#       redirect_to admin_identity_submissions_path
#     end
#   end

#   # -------------------------------------------------------------------------
#   # === Partner Context Management
#   # -------------------------------------------------------------------------
#   def store_partner_context
#     PartnerSessionService.new(session, params).store!
#   end

#   def set_partner_from_slug
#     return unless params[:partner_slug].present?

#     @partner = Partner.find_by(slug: params[:partner_slug])
#     if @partner.present?
#       Rails.logger.info("🏦 Partner context loaded: #{@partner.name} (slug: #{@partner.slug})")
#       session[:login_source] = "partner:#{@partner.slug}"
#     else
#       Rails.logger.warn("⚠️ Partner slug not found: #{params[:partner_slug]}")
#     end
#   end

#   # -------------------------------------------------------------------------
#   # === Role-Aware Account Enforcement
#   # -------------------------------------------------------------------------
#   def ensure_active_account!
#     resource = current_resource
#     role = current_role
#     return unless role.in?([ :partner_admin, :banker, :banking_agent ])
#     return unless resource.respond_to?(:active?) && !resource.active?

#     sign_out(resource)
#     redirect_to new_partner_admin_session_path,
#                 alert: "🚫 Your BonID access has been suspended by your organization."
#   end
# end

# # app/controllers/application_controller.rb
# class ApplicationController < ActionController::Base
#   include Pundit::Authorization
#   allow_browser versions: :modern
#   protect_from_forgery with: :exception

#   # === Before Actions ===
#   before_action :configure_permitted_parameters, if: :devise_controller?
#   before_action :set_turbo_frame_request_variant
#   before_action :redirect_admin_from_user_dashboard, if: :any_user_signed_in?
#   before_action :block_user_on_officer_routes
#   before_action :require_password_confirmation, if: :sensitive_area?
#   before_action :store_partner_context
#   before_action :enforce_namespace_access

#   helper_method :safe_current_user
#   helper_method :profile_complete?, :current_role, :any_user_signed_in?

#   # === Safe current_user/officer presence check ===
#   def any_user_signed_in?
#     (defined?(current_user) && current_user.present?) ||
#       (defined?(current_officer) && current_officer.present?)
#   end

#   # === Role Helper ===
#   def current_role
#     if defined?(current_officer) && current_officer
#       :officer
#     elsif defined?(current_user) && current_user&.admin?
#       :admin
#     elsif defined?(current_user) && current_user&.partner_admin?
#       :partner_admin
#     elsif defined?(current_user) && current_user&.citizen?
#       :citizen
#     else
#       nil
#     end
#   end

#   # === Enforce namespace routing ===
#   def enforce_namespace_access
#     role = current_role
#     return unless role # skip if no one logged in

#     user_id = (defined?(current_user) && current_user&.id) ||
#               (defined?(current_officer) && current_officer&.id)

#     Rails.logger.info "[ACCESS CHECK] role=#{role} id=#{user_id} path=#{request.path}"

#     begin
#       allowed_paths = ::AccessControl::ROLE_NAMESPACE_ACCESS[role] || []
#     rescue NameError => e
#       Rails.logger.error "[FATAL] AccessControl not loaded: #{e.message}, role=#{role}, id=#{user_id}, path=#{request.path}"
#       if request.path == "/" || (role == :admin && request.path.start_with?("/admin"))
#         return
#       else
#         redirect_to root_path, alert: "System error: Access control configuration missing. Please contact support."
#         return
#       end
#     end

#     return if request.path == "/" # Allow root_path

#     unless allowed_paths.any? { |prefix| request.path.start_with?(prefix) }
#       Rails.logger.warn "[ACCESS BLOCKED] role=#{role} id=#{user_id} tried to access #{request.path}"

#       alert_msg = case role
#       when :citizen      then "🚫 Citizens cannot access this area."
#       when :partner_admin then "🚫 Partner admins cannot access officer routes."
#       when :admin        then "🚫 Admins cannot access this area."
#       when :officer      then "🚫 Officers cannot access this area."
#       else "🚫 Access denied for your role."
#       end

#       redirect_to RoleRedirectService.redirect_path_for(
#                     (defined?(current_user) && current_user) || current_officer
#                   ),
#                   alert: alert_msg
#     end
#   end

#   # === Pundit Support ===
#   def pundit_user
#     (defined?(current_officer) && current_officer) || current_user
#   end

#   # === Devise Redirections ===
#   def after_sign_in_path_for(resource_or_scope)
#     resource = resource_or_scope.is_a?(Symbol) ? (defined?(current_user) && current_user) : resource_or_scope
#     RoleRedirectService.redirect_path_for(resource) ||
#       stored_location_for(resource) ||
#       root_path
#   end

#   def after_sign_out_path_for(resource_or_scope)
#     flash.clear
#     case resource_or_scope
#     when :officer, Officer
#       flash[:notice] = "You have been signed out of the Officer Portal."
#     end
#     root_path
#   end

#   # === Authentication Helpers ===
#   def authenticate_any!
#     request.path.start_with?("/officers") ? authenticate_officer! : authenticate_user!
#   end

#   def require_officer!
#     OfficerAccessPolicy.new(current_officer).authorize!
#   rescue Pundit::NotAuthorizedError => e
#     redirect_to root_path, alert: e.message
#   end

#   def block_user_on_officer_routes
#     if request.path.start_with?("/officers") && (defined?(user_signed_in?) && user_signed_in?)
#       sign_out current_user if defined?(current_user)
#       redirect_to root_path, alert: "🚫 Access restricted to verified officers of the Haitian National Police (PNH)."
#     end
#   end

#   def redirect_admin_from_user_dashboard
#     if defined?(current_user) && current_user&.admin? && request.path == user_dashboard_path
#       redirect_to admin_identity_submissions_path
#     end
#   end

#   # === Profile Completion ===
#   def profile_complete?(user)
#     UserProfilePolicy.new(user).complete?
#   end

#   # === Devise Parameter Whitelisting ===
#   def configure_permitted_parameters
#     devise_parameter_sanitizer.permit(:sign_up, keys: %i[email password password_confirmation terms])
#     devise_parameter_sanitizer.permit(:account_update, keys: UserProfilePolicy.permitted_params)
#   end


# def safe_current_user
#   defined?(current_user) ? current_user : nil
# end


#   # === Turbo Support ===
#   def set_turbo_frame_request_variant
#     request.variant = :turbo_frame if turbo_frame_request?
#   end

#   def sensitive_area?
#     !devise_controller? && controller_name.in?(%w[settings payments critical_actions])
#   end

#   def require_password_confirmation
#     return unless defined?(current_officer) && current_officer
#     unless OfficerPasswordPolicy.new(current_officer).recently_confirmed?
#       store_location_for(:officer, request.fullpath)
#       redirect_to new_officer_password_confirmation_path
#     end
#   end

#   # === Partner Context ===
#   def store_partner_context
#     PartnerSessionService.new(session, params).store!
#   end
# end
