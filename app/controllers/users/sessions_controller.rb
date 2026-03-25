module Users
  class SessionsController < Devise::SessionsController
    before_action :redirect_to_role_specific_login, only: :new,
                  if: -> { any_user_signed_in? && request.path == user_session_path }

    ROLE_RESTRICTIONS = {
      "/admin/sign_in"         => :admin,
      "/partner_admin/sign_in" => :partner_admin,
      "/reviewer/sign_in"      => :reviewer
    }.freeze

    def new
      if officer_signed_in?
        redirect_to officers_dashboard_path,
                    alert: I18n.t("sessions.already_signed_in_officer",
                                  default: "You are already signed in as an Officer.")
      elsif any_user_signed_in?
        redirect_to_role_specific_path(
          notice: I18n.t("sessions.use_role_specific",
                         default: "Please use your role-specific login page.")
        )
      else
        @role = case request.path
        when new_admin_session_path         then "System Admin"
        when new_partner_admin_session_path then "Partner Admin"
        when new_reviewer_session_path      then "Reviewer"
        when new_citizen_session_path, citizens_otp_sign_in_path then "Citizen"
        when new_officer_session_path       then "Officer"
        else "User"
        end
        super
      end
    end

    def create
      # ✅ Normalize params so Devise always sees params[:user]
      creds = params[:user] || params[:admin] || params[:partner_admin] ||
              params[:reviewer] || params[:citizen] || params[:officer] || {}
      params[:user] = creds if creds.present?

      # --- Devise authentication ---
      self.resource = warden.authenticate(auth_options)

      if resource
        # --- Route-based role restrictions (after auth) ---
        if (required_role = ROLE_RESTRICTIONS[request.path])
          unless resource.has_role?(required_role)
            sign_out resource
            flash[:alert] = "Only #{required_role.to_s.humanize} can log in here."
            return redirect_to RoleRedirectService.login_path_for(request.path)
          end
        end

        # --- Special Partner Admin approval check ---
        if request.path == partner_admin_session_path
          if resource.has_role?(:partner_admin) && !resource.partner
            sign_out resource
            flash[:alert] = "Your Partner Admin application is pending approval."
            return redirect_to new_partner_admin_session_path
          end
        end

        flash[:notice] = I18n.t("devise.sessions.signed_in")
        sign_in(resource_name, resource)
        redirect_to after_sign_in_path_for(resource)
      else
        flash[:alert] = I18n.t("devise.failure.invalid", authentication_keys: "email")
        redirect_to RoleRedirectService.login_path_for(request.path)
      end
    end

    protected

    # ✅ always send to correct dashboard
    def after_sign_in_path_for(resource)
      RoleRedirectService.redirect_path_for(resource)
    end

    def after_sign_out_path_for(_resource_or_scope)
      root_path
    end

    private

    def any_user_signed_in?
      (defined?(current_user) && current_user.present?) ||
        (defined?(current_officer) && current_officer.present?)
    end

    def redirect_to_role_specific_login
      role = if defined?(current_user) && current_user
               # HABTM: check first role name safely
               current_user.roles.first&.name&.to_sym
      elsif defined?(current_officer) && current_officer
               :officer
      else
               :guest
      end

      redirect_path = case role
      when :citizen       then citizens_otp_sign_in_path
      when :admin         then new_admin_user_session_path
      when :partner_admin then new_partner_admin_session_path
      when :officer       then new_officer_session_path
      when :reviewer      then new_reviewer_session_path
      else root_path
      end

      Rails.logger.info "[USER SIGN_IN] Redirecting to role-specific login: #{redirect_path}, role: #{role}"
      redirect_to redirect_path unless request.path == redirect_path
    end

    def redirect_to_role_specific_path(notice: nil)
      path = if defined?(current_user) && current_user
               RoleRedirectService.login_path_for(request.path)
      elsif defined?(current_officer) && current_officer
               new_officer_session_path
      else
               root_path
      end
      redirect_to path, notice: notice
    end
  end
end


# # app/controllers/users/sessions_controller.rb
# module Users
#   class SessionsController < Devise::SessionsController
#     before_action :redirect_to_role_specific_login, only: :new,
#                   if: -> { any_user_signed_in? && request.path == user_session_path }

#     ROLE_RESTRICTIONS = {
#       "/admin/sign_in"         => :admin,
#       "/partner_admin/sign_in" => :partner_admin,
#       "/reviewer/sign_in"      => :reviewer
#     }.freeze

#     def new
#       if officer_signed_in?
#         redirect_to officers_dashboard_path,
#                     alert: I18n.t("sessions.already_signed_in_officer",
#                                   default: "You are already signed in as an Officer.")
#       elsif any_user_signed_in?
#         redirect_to_role_specific_path(
#           notice: I18n.t("sessions.use_role_specific",
#                          default: "Please use your role-specific login page.")
#         )
#       else
#         @role = case request.path
#         when new_admin_session_path         then "System Admin"
#         when new_partner_admin_session_path then "Partner Admin"
#         when new_reviewer_session_path      then "Reviewer"
#         when new_citizen_session_path, citizens_otp_sign_in_path then "Citizen"
#         when new_officer_session_path       then "Officer"
#         else "User"
#         end
#         super
#       end
#     end

#     def create
#       # ✅ Normalize params so Devise always sees params[:user]
#       creds = params[:user] || params[:admin] || params[:partner_admin] ||
#               params[:reviewer] || params[:citizen] || params[:officer] || {}
#       params[:user] = creds if creds.present?

#       email = creds[:email].to_s.strip.downcase
#       user  = User.find_by(email: email)

#       # --- Route-based role restrictions (DRY) ---
#       if (required_role = ROLE_RESTRICTIONS[request.path])
#         unless user&.has_role?(required_role)
#           flash[:alert] = "Only #{required_role.to_s.humanize} can log in here."
#           return redirect_to RoleRedirectService.login_path_for(request.path)
#         end
#       end

#       # --- Special Partner Admin approval check ---
#       if request.path == partner_admin_session_path
#         if user&.partner_admin? && !user.partner
#           flash[:alert] = "Your Partner Admin application is pending approval."
#           return redirect_to new_partner_admin_session_path
#         end
#       end

#       # --- Devise authentication ---
#       self.resource = warden.authenticate(auth_options)
#       if resource
#         flash[:notice] = I18n.t("devise.sessions.signed_in")
#         sign_in(resource_name, resource)
#         redirect_to after_sign_in_path_for(resource)
#       else
#         flash[:alert] = I18n.t("devise.failure.invalid", authentication_keys: "email")
#         redirect_to RoleRedirectService.login_path_for(request.path)
#       end
#     end

#     protected

#     def after_sign_in_path_for(resource)
#       ::UserRedirectService.after_sign_in_path_for(resource, session) ||
#         default_after_sign_in_path(resource)
#     end

#     def after_sign_out_path_for(_resource_or_scope)
#       root_path
#     end

#     private

#     def any_user_signed_in?
#       (defined?(current_user) && current_user.present?) ||
#         (defined?(current_officer) && current_officer.present?)
#     end

#     def redirect_to_role_specific_login
#       role = if defined?(current_user) && current_user
#                current_user.role.to_sym
#       elsif defined?(current_officer) && current_officer
#                :officer
#       else
#                :guest
#       end

#       redirect_path = case role
#       when :citizen       then citizens_otp_sign_in_path
#       when :admin         then new_admin_user_session_path
#       when :partner_admin then new_partner_admin_session_path
#       when :officer       then new_officer_session_path
#       when :reviewer      then new_reviewer_session_path
#       else root_path
#       end

#       Rails.logger.info "[USER SIGN_IN] Redirecting to role-specific login: #{redirect_path}, role: #{role}"
#       redirect_to redirect_path unless request.path == redirect_path
#     end

#     def redirect_to_role_specific_path(notice: nil)
#       path = if defined?(current_user) && current_user
#                RoleRedirectService.login_path_for(request.path)
#       elsif defined?(current_officer) && current_officer
#                new_officer_session_path
#       else
#                root_path
#       end
#       redirect_to path, notice: notice
#     end
#   end
# end



# module Users
#   class SessionsController < Devise::SessionsController
#     def new
#       if officer_signed_in?
#         redirect_to officers_dashboard_path, alert: I18n.t('sessions.already_signed_in_officer')
#       else
#         super
#       end
#     end

#     def create
#       email = params[:user][:email].to_s.strip.downcase
#       user = User.find_by(email: email)

#       # Partner admins must log in through partner portal
#       if user&.role_int == 'partner_admin'
#         flash[:alert] = I18n.t('sessions.partner_admin_email') # "Partner admins must log in via their portal."
#         redirect_to new_partner_admin_session_path and return
#       end

#       self.resource = warden.authenticate(auth_options)

#       if resource
#         # Allow all valid users including officers to log in here
#         flash[:notice] = I18n.t("devise.sessions.signed_in")
#         sign_in(resource_name, resource)
#         redirect_to after_sign_in_path_for(resource)
#       else
#         flash[:alert] = I18n.t("devise.failure.invalid", authentication_keys: "email")
#         redirect_to new_user_session_path
#       end
#     end

#     protected

#     def after_sign_in_path_for(resource)
#       ::UserRedirectService.after_sign_in_path_for(resource, session)
#     end

#     def after_sign_out_path_for(_resource_or_scope)
#       root_path
#     end
#   end
# end
