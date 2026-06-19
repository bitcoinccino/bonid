# app/controllers/officers/invitations_controller.rb
module Officers
  class InvitationsController < Devise::InvitationsController
    layout "officer_auth", only: [ :edit, :update ]

    # Skip Devise's default token lookup (looks in Officer model)
    # We use find_user_by_token which looks in User model instead
    skip_before_action :resource_from_invitation_token, only: [ :edit, :update ]

    before_action :authenticate_scope!, except: [ :edit, :update, :accept ]
    before_action :find_user_by_token, only: [ :edit, :update, :accept ]
    before_action :reject_if_already_signed_in, only: [ :edit, :update, :accept ]

    # GET /officers/invitation/accept?invitation_token=xxxx
    def accept
      # Check if user exists and has officer role (or Officer record)
      unless @user && (@user.has_role?(:officer) || @user.officer.present?)
        flash[:alert] = I18n.t("devise.invitations.invalid_token")
        return redirect_to new_officer_session_path
      end

      redirect_to edit_officer_invitation_path(invitation_token: params[:invitation_token])
    end

    # GET /officers/invitation/edit?invitation_token=xxxx
    def edit
      # Check if user exists and has officer role (or Officer record)
      unless @user && (@user.has_role?(:officer) || @user.officer.present?)
        flash[:alert] = I18n.t("devise.invitations.invalid_token")
        redirect_to new_officer_session_path
      end
    end

    # PUT /officers/invitation
    def update
      unless @user
        flash[:alert] = I18n.t("devise.invitations.invalid_token")
        return redirect_to new_officer_session_path
      end

      password = officer_params[:password]
      password_confirmation = officer_params[:password_confirmation]

      # Guard explicitly: Devise's :validatable skips the password presence
      # check on an already-persisted User when the field is blank, so a blank
      # submission would otherwise sail through without ever setting a password.
      if password.blank?
        flash.now[:alert] = "Tanpri chwazi yon modpas."
        return render :edit, status: :unprocessable_entity
      end

      if password != password_confirmation
        flash.now[:alert] = "Modpas yo pa menm."
        return render :edit, status: :unprocessable_entity
      end

      ActiveRecord::Base.transaction do
        # Update the underlying User identity with the chosen password
        @user.update!(
          password: password,
          password_confirmation: password_confirmation,
          invitation_token: nil,
          invitation_accepted_at: Time.current
        )

        # Ensure officer role is set
        @user.add_role(:officer) unless @user.has_role?(:officer)

        # The Officer record is normally pre-created at invite time (with real
        # rank/unit/badge) carrying a random throwaway password. Acceptance MUST
        # write the officer's chosen password onto that record — without this the
        # officer can never sign in (they'd be stuck with the random password).
        # Only fill placeholders when the Officer record is genuinely missing.
        officer = @user.officer || @user.build_officer
        if officer.new_record?
          officer.assign_attributes(
            email:      @user.email,
            first_name: @user.first_name || "Pending",
            last_name:  @user.last_name  || "Setup",
            partner_id: @user.partner_id,
            badge_id:   "PENDING-#{SecureRandom.hex(4).upcase}",
            rank:       "Agent",
            unit_name:  "UDMO",
            unit_type:  "Patrouille Urbaine",
            status:     :invited
          )
        end

        # Always set on accept — for both new and pre-created officers.
        officer.email                  ||= @user.email
        officer.password                 = password
        officer.password_confirmation    = password_confirmation
        officer.invitation_token         = nil
        officer.invitation_accepted_at   = Time.current
        officer.save!(validate: false) # profile completed in onboarding

        # Sign in as the Officer
        sign_in(:officer, officer)

        flash[:notice] = "Welcome! Please complete your officer profile to continue."
        redirect_to officers_onboarding_path
      end
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "Officer invitation acceptance failed: #{e.message}"
      flash.now[:alert] = "Could not complete setup: #{e.record.errors.full_messages.join(', ')}"
      render :edit, status: :unprocessable_entity
    end

    protected

    def after_accept_path_for(resource)
      if resource.identity_submissions.approved.exists?
        officers_dashboard_path
      else
        flash[:alert] = I18n.t("devise.invitations.bonid_not_verified")
        new_identity_submission_path
      end
    end

    private

    def authenticate_scope!
      send("authenticate_#{resource_name}!") unless action_name.in?(%w[edit update accept])
    end

    def resource_name
      :officer
    end

    def find_user_by_token
      raw_token = params[:invitation_token] ||
                  params[:token] ||
                  params.dig(:officer, :invitation_token)

      if raw_token.blank?
        Rails.logger.debug "[INVITE DEBUG] No raw token in params"
        @user = nil
        return
      end

      digested = Devise.token_generator.digest(User, :invitation_token, raw_token)

      Rails.logger.debug "[INVITE DEBUG] Raw Token: #{raw_token}"
      Rails.logger.debug "[INVITE DEBUG] Digested Token: #{digested}"

      @user = User.find_by(invitation_token: digested)

      # Set resource for Devise views compatibility
      self.resource = @user if @user

      unless @user
        Rails.logger.debug "[INVITE DEBUG] No user found for token"
        flash[:alert] = I18n.t("devise.invitations.invalid_token")
        redirect_to new_officer_session_path
      end
    end

    def reject_if_already_signed_in
      if officer_signed_in?
        sign_out_all_scopes
        flash[:alert] = I18n.t("devise.invitations.already_signed_in")
        redirect_to new_officer_session_path
      end
    end

    def officer_params
      params.require(:officer).permit(
        :invitation_token, # ✅ added so token flows through update
        :password, :password_confirmation,
        :unit_name, :unit_type, :first_name, :last_name, :rank
      )
    end

    def respond_failure
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "invitation-form",
            partial: "officers/invitations/form",
            locals: { officer: @user.try(:officer) }
          )
        end
        format.html do
          flash.now[:alert] = I18n.t(
            "devise.invitations.form_error",
            default: "Please fix the errors below."
          )
          render :edit, status: :unprocessable_entity
        end
      end
    end
  end
end
