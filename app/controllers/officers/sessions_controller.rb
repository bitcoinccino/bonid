# app/controllers/officers/sessions_controller.rb
module Officers
  class SessionsController < Devise::SessionsController
    layout "officer_auth"
    respond_to :html, :turbo_stream

    # === GET /officers/sign_in ===
    def new
      # Preserve any flash message that arrived via redirect (e.g. revocation alert)
      # before sign_out_all_scopes resets the session and wipes it.
      preserved_alert  = flash[:alert]
      preserved_error  = flash[:error]
      preserved_notice = flash[:notice]

      sign_out_all_scopes

      # Restore into flash.now so it renders on this response without being
      # cleared by the sign_out session reset.
      flash.now[:alert]  = preserved_alert  if preserved_alert.present?
      flash.now[:error]  = preserved_error  if preserved_error.present?
      flash.now[:notice] = preserved_notice if preserved_notice.present?

      self.resource = resource_class.new
      resource.email = "" if resource.respond_to?(:email)
      clean_up_passwords(resource)
      respond_with(resource, serialize_options(resource))
    end

    # === POST /officers/sign_in ===
    def create
      email = params.dig(:officer, :email).to_s.strip.downcase
      Rails.logger.info "🔐 Officer login attempt: #{email} @ #{Time.current}"

      self.resource = warden.authenticate(auth_options)
      officer = resource

      error, error_type = officer_error(officer)
      return respond_with_error(error, type: error_type) if error

      sign_in(:officer, officer)
      flash[:notice] = "Welcome, Officer #{officer.full_name}!"
      Rails.logger.info "✅ Officer login success: #{officer.full_name} (Officer ID #{officer.id})"

      redirect_path = after_sign_in_path_for(officer)

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("flash", partial: "shared/flash"),
            turbo_stream.replace(
              "turbo-redirect",
              partial: "shared/turbo_redirect",
              locals: { redirect_path: redirect_path }
            )
          ]
        end
        format.html { redirect_to redirect_path }
        format.json { render json: { success: true, redirect: redirect_path }, status: :ok }
      end
    rescue => e
      Rails.logger.error("❌ Officer sign-in failed: #{e.message}")
      respond_with_error("Unexpected error during sign-in. Please try again.")
    end

    # === DELETE /officers/sign_out ===
    def destroy
      clear_officer_session!
      super
    end

    protected

    # Redirect to onboarding if officer hasn't completed profile, otherwise to dashboard
    def after_sign_in_path_for(officer)
      # If badge_id starts with PENDING-, officer needs to complete onboarding
      if officer.badge_id.to_s.start_with?("PENDING-")
        officers_onboarding_path
      else
        officers_dashboard_path
      end
    end

    def after_sign_out_path_for(_resource_or_scope)
      clear_officer_session!
      new_officer_session_path
    end

    private

    # === Officer validation chain ===
    # Returns [message, flash_type] on failure, or nil on success.
    # flash_type is :alert (yellow/warning) or :error (red/danger).
    def officer_error(officer)
      return [ "Email ou mot de passe incorrect. Veuillez réessayer.", :alert ] unless officer.present?

      unless officer.invitation_accepted_at.present? || officer.encrypted_password.present?
        return [ "Vous n'avez pas encore accepté votre invitation. Vérifiez votre email.", :alert ]
      end

      # Revoked — red, not yellow
      if officer.revoked?
        return [ "Votre accès a été révoqué. Veuillez contacter votre administrateur.", :error ]
      end

      unless officer.status.in?(%w[active invited])
        return [ "Votre compte n'est pas autorisé à accéder au portail.", :error ]
      end

      nil
    end

    # === Error handler ===
    def respond_with_error(message, type: :alert)
      Rails.logger.info "🚨 Officer login error: #{message}"
      respond_to do |format|
        format.turbo_stream do
          flash.now[type] = message
          render turbo_stream: turbo_stream.replace("flash", partial: "shared/flash"),
                 status: :unprocessable_entity
        end
        format.html do
          flash.now[type] = message
          self.resource = resource_class.new
          clean_up_passwords(resource)
          render :new, status: :unprocessable_entity
        end
        format.json { render json: { error: message }, status: :unauthorized }
      end
    end

    # === Cleanup helpers ===
    def clear_officer_session!
      session.delete(:officer_id)
      session.delete(:bonid_partner_id)
    end
  end
end


# module Officers
#   class SessionsController < Devise::SessionsController
#     layout "officer_auth"
#     before_action :redirect_if_authenticated, only: [ :new ]
#     before_action :block_if_user_signed_in, only: [ :new, :create ]

#     def create
#       email = params.dig(:officer, :email).to_s.strip.downcase
#       Rails.logger.info " Officer login attempt: #{email} @ #{Time.current}"

#       self.resource = warden.authenticate(auth_options)

#       unless resource&.role_int == User.role_ints[:officer]
#         Rails.logger.warn " Not an officer email: #{email}"
#         return respond_with_error(I18n.t("sessions.non_officer_email"))
#       end

#       user = resource
#       officer = user.officer

#       unless officer
#         Rails.logger.warn " No Officer record for user ID #{user.id} (#{email})"
#         return respond_with_error(I18n.t("sessions.no_officer_record"))
#       end

#       unless officer.invitation_accepted_at.present? || officer.encrypted_password.present?
#         Rails.logger.warn " Officer has not accepted invitation or set password"
#         return respond_with_error(I18n.t("sessions.invitation_not_accepted"))
#       end

#       unless officer.status_approved?
#         Rails.logger.warn " Officer #{officer.id} pending approval"
#         return respond_with_error(I18n.t("sessions.pending_approval"))
#       end

#       unless user.has_verified_bonid?
#         Rails.logger.warn "❗ Officer #{officer.id} has no verified BonID"
#         return respond_with_error(I18n.t("sessions.bonid_not_verified"))
#       end

#       sign_in(:officer, user)
#       flash[:notice] = I18n.t("sessions.officer_welcome")
#       Rails.logger.info "Officer login success: #{officer.full_name} (ID #{officer.id})"

#       redirect_path = ::UserRedirectService.after_sign_in_path_for(user, session)

#       respond_to do |format|
#         format.turbo_stream do
#           render turbo_stream: [
#             turbo_stream.replace("flash", partial: "shared/flash"),
#             turbo_stream.replace("turbo-redirect", partial: "shared/turbo_redirect", locals: { redirect_path: redirect_path })
#           ]
#         end
#         format.html { redirect_to redirect_path }
#         format.json { render json: { success: true }, status: :ok }
#       end
#     end

#     def destroy
#       clear_officer_session!
#       super
#     end

#     protected

#     def after_sign_in_path_for(resource)
#       ::UserRedirectService.after_sign_in_path_for(resource, session)
#     end

#     def after_sign_out_path_for(_resource_or_scope)
#       clear_officer_session!
#       new_officer_session_path
#     end

#     private

#     def respond_with_error(message)
#       Rails.logger.info "Login error: #{message}"
#       respond_to do |format|
#         format.turbo_stream do
#           flash.now[:alert] = message
#           render turbo_stream: turbo_stream.replace("flash", partial: "shared/flash"), status: :unprocessable_entity
#         end
#         format.html do
#           flash[:alert] = message
#           redirect_to new_officer_session_path
#         end
#         format.json { render json: { error: message }, status: :unauthorized }
#       end
#     end

#     def redirect_if_authenticated
#       if officer_signed_in?
#         flash[:notice] = I18n.t("sessions.officer_restricted")
#         redirect_to ::UserRedirectService.after_sign_in_path_for(current_officer, session)
#       end
#     end

#     def block_if_user_signed_in
#       if user_signed_in?
#         officer_email = params.dig(:officer, :email)&.downcase
#         user_email = current_user.email.downcase
#         if officer_email.present? && user_email != officer_email
#           flash[:alert] = I18n.t("sessions.user_signed_in")
#           redirect_to root_path
#         end
#       end
#     end

#     def clear_officer_session!
#       session.delete(:officer_id)
#       session.delete(:bonid_partner_id)
#     end
#   end
# end
