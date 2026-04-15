# frozen_string_literal: true

class PartnerSetupService
  include Rails.application.routes.url_helpers

  def initialize(partner:, admin_user:)
    @partner = partner
    @admin_user = admin_user
  end

  # ============================================================================
  # APPROVE PARTNER
  # ============================================================================
  def approve!
    ActiveRecord::Base.transaction do
      generate_api_key! if @partner.api_key_digest.blank?

      @partner.update!(
        verified_at: Time.current,
        active: true,
        admin_user_id: @admin_user.id,
        status: :approved
      )

      setup_partner_admin!
      setup_default_teller! if @partner.sector == "banking"
      provision_oauth_credentials!
      generate_webhook_secret!
    end

    true
  rescue => e
    Rails.logger.error "🚨 PartnerSetupService#approve! FAILED: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.join("\n") if Rails.env.development?
    false
  end

  # ============================================================================
  # REJECT PARTNER — Full Correct Flow
  # ============================================================================
  def reject!(reason:, comment: nil)
    ActiveRecord::Base.transaction do
      @partner.update!(
        status: :rejected,
        verified_at: nil,
        active: false,
        rejection_reason: reason,
        rejection_comment: comment.presence,
      )

      PartnerAuditLog.create!(
        partner: @partner,
        admin_user: @admin_user,
        event: "partner_rejected",
        details: {
          reason: reason,
          comment: comment,
          ip: Current.request&.ip
        }
      )
    end

    true
  rescue => e
    Rails.logger.error "🚨 PartnerSetupService#reject! FAILED: #{e.class} - #{e.message}"
    false
  end

  # ============================================================================
  # PRIVATE HELPERS
  # ============================================================================
  private

  # ============================================================================
  # API KEY GENERATION (SHA256)
  # ============================================================================
  def generate_api_key!
    raw_key = "bonid_#{@partner.slug}_#{SecureRandom.hex(16)}"
    digest  = OpenSSL::Digest::SHA256.hexdigest(raw_key)

    @partner.update!(
      api_key_digest: digest,
      api_key_rotated_at: Time.current
    )

    Rails.logger.info "🔑 API key generated for #{@partner.name} — COPY NOW: #{raw_key}"
    raw_key
  end

  # ============================================================================
  # PARTNER ADMIN ACCOUNT
  # ============================================================================
  def setup_partner_admin!
    user = User.find_or_initialize_by(email: @partner.email)

    # ✅ Remove any existing roles (especially citizen) before adding partner_admin
    if user.persisted?
      user.roles.each do |role|
        user.remove_role(role.name) unless role.name == "partner_admin"
      end
    end

    user.assign_attributes(
      first_name: @partner.contact_person.presence || "Partner",
      last_name:  "Admin",
      partner_id: @partner.id
    )

    ensure_password(user)
    user.save!

    # ✅ Add partner_admin role before sending invitation
    user.add_role(:partner_admin) unless user.has_role?(:partner_admin)
    send_invite_email(user, :partner_admin)
  end

  # ============================================================================
  # BANKING DEFAULT TELLER
  # ============================================================================
  def setup_default_teller!
    return unless @partner.sector == "banking"

    email = "agent@#{@partner.slug}.ht"
    user = User.find_or_initialize_by(email: email)

    user.assign_attributes(
      first_name: "Default",
      last_name:  "Agent",
      partner_id: @partner.id
    )

    ensure_password(user, "Teller123!")
    user.save!

    user.add_role(:banking_agent)
  end

  # ============================================================================
  # LAW ENFORCEMENT ADMIN
  # ============================================================================
  def setup_officer_admin!
    user = User.find_or_initialize_by(email: @partner.email)

    # ✅ Remove any existing roles (especially citizen) before adding officer roles
    if user.persisted?
      user.roles.each do |role|
        user.remove_role(role.name) unless [:officer, :partner_admin].include?(role.name.to_sym)
      end
    end

    user.assign_attributes(
      first_name: @partner.contact_person.presence || "Officer",
      last_name:  @partner.name,
      partner_id: @partner.id
    )

    ensure_password(user)
    user.save!

    user.add_role(:officer) unless user.has_role?(:officer)
    user.add_role(:partner_admin) unless user.has_role?(:partner_admin)

    # Partner form stores unit keys (DCPJ, CIMO) in unit_type and sub-specialties
    # in unit_name, but Officer model expects the reverse:
    #   Officer.unit_name = UNIT_OPTIONS.keys (e.g. "CIMO")
    #   Officer.unit_type = UNIT_OPTIONS.values.flatten (e.g. "Contrôle des Foules")
    resolved_unit_name = @partner.unit_type.presence || "CIMO"
    resolved_unit_type = @partner.unit_name.presence || OfficerConstants::UNIT_OPTIONS[resolved_unit_name]&.first || "Contrôle des Foules"

    officer = Officer.find_or_initialize_by(email: @partner.email)
    officer.assign_attributes(
      first_name: user.first_name,
      last_name:  user.last_name,
      partner:    @partner,
      user:       user,
      unit_name:  resolved_unit_name,
      unit_type:  resolved_unit_type,
      badge_id:   "PNH-#{SecureRandom.hex(4).upcase}",
      rank:       "Agent I"
    )
    ensure_password(officer)
    officer.save!

    send_invite_email(user, :officer)
  end

  # ============================================================================
  # OAUTH APPLICATION (Auto-provisioned on approval)
  # ============================================================================
  def provision_oauth_credentials!
    return if OauthApplication.exists?(partner_id: @partner.id)

    plain_secret = SecureRandom.hex(32)
    app = OauthApplication.create!(
      partner: @partner,
      name: @partner.name,
      uid: SecureRandom.uuid,
      secret_digest: BCrypt::Password.create(plain_secret),
      redirect_uri: @partner.primary_redirect_uri || "urn:ietf:wg:oauth:2.0:oob"
    )

    # Create one-time secret portal link (expires in 72 hours, viewable once)
    secret = OneTimeSecret.create_for(
      partner: @partner,
      payload: { client_id: app.uid, client_secret: plain_secret },
      label: "OAuth Credentials",
      expires_in: 72.hours
    )

    @oauth_secret_url = secret.url

    PartnerAuditLog.create!(
      partner: @partner,
      admin_user: @admin_user,
      event: "oauth_credentials_provisioned",
      details: "OAuth application created. Credentials available via one-time secret link.",
      metadata: { client_id: app.uid, secret_token: secret.token }
    )

    Rails.logger.info "[PartnerSetup] OAuth credentials provisioned for #{@partner.name} — client_id: #{app.uid}"
  end

  # ============================================================================
  # WEBHOOK SECRET (Auto-generated on approval)
  # ============================================================================
  def generate_webhook_secret!
    return if @partner.webhook_secret.present?

    @partner.update!(webhook_secret: SecureRandom.hex(32))
    Rails.logger.info "[PartnerSetup] Webhook secret generated for #{@partner.name}"
  end

  # ============================================================================
  # PASSWORD GENERATION
  # ============================================================================
  def ensure_password(user, default = SecureRandom.hex(8))
    if user.new_record? || user.encrypted_password.blank?
      user.password = user.password_confirmation = default
    end
  end

  # ============================================================================
  # SEND INVITE EMAIL
  # ============================================================================
  def send_invite_email(user, role)
    raw, enc = Devise.token_generator.generate(User, :reset_password_token)

    user.update!(
      reset_password_token: enc,
      reset_password_sent_at: Time.current
    )

    host =
      Rails.application.routes.default_url_options[:host].presence ||
      ENV["APP_HOST"].presence ||
      "http://localhost:3000"

    invite_url =
      case role
      when :partner_admin
        edit_partner_admin_password_url(reset_password_token: raw, host: host)
      when :officer
        edit_officer_password_url(reset_password_token: raw, host: host)
      end

    Admin::PartnerAdminMailer.invite(
      partner: @partner,
      email: user.email,
      invite_url: invite_url,
      oauth_secret_url: @oauth_secret_url
    ).deliver_later
  end
end


# # frozen_string_literal: true

# # Service: PartnerSetupService
# # Purpose:
# #   Handles full partner onboarding lifecycle — approval, rejection,
# #   admin invitation, API key generation, and optional default agent setup.
# #
# #   Ensures idempotent execution and secure transactional updates.
# #
# # Author: BonID Core Team (Rails 8 / Ruby 3.3)
# class PartnerSetupService
#   include Rails.application.routes.url_helpers

#   def initialize(partner, current_admin_user)
#     @partner = partner
#     @current_admin_user = current_admin_user
#   end

#   # === APPROVE PARTNER ===
#   def approve!
#     ActiveRecord::Base.transaction do
#       generate_api_key! unless @partner.api_key_digest.present?

#       @partner.update!(
#         verified_at:   Time.current,
#         active:        true,
#         admin_user_id: @current_admin_user.id
#       )

#       case @partner.sector
#       when "law_enforcement"
#         setup_officer_admin_account!
#       when "banking"
#         onboard_partner_admin!
#         create_default_teller_agent!
#       else
#         onboard_partner_admin!
#       end

#       Rails.logger.info "✅ Partner #{@partner.name} approved; onboarding initialized."
#     end

#     true
#   rescue => e
#     Rails.logger.error "🚨 PartnerSetupService#approve! failed: #{e.class}: #{e.message}"
#     Rails.logger.error e.backtrace.join("\n") if Rails.env.development?
#     false
#   end

#   # === REJECT PARTNER ===
#   def reject!(reason:, comment: nil)
#     ActiveRecord::Base.transaction do
#       @partner.update!(
#         verified_at: nil,
#         active: false,
#         rejection_reason: reason,
#         rejection_comment: comment
#       )
#     end

#     Admin::PartnerAdminMailer.rejected(partner: @partner).deliver_later
#     true
#   rescue => e
#     Rails.logger.error "🚨 PartnerSetupService#reject! failed: #{e.class}: #{e.message}"
#     false
#   end

#   private

#   # ---------------------------------------------------------------
#   #  🔐 API KEY GENERATION
#   # ---------------------------------------------------------------
#   def generate_api_key!
#     require "securerandom"
#     require "bcrypt"

#     api_key = "bonid_#{@partner.slug}_#{SecureRandom.hex(8)}"
#     digest = BCrypt::Password.create(api_key)
#     @partner.update!(api_key_digest: digest)

#     Rails.logger.info "🔑 Generated API key for #{@partner.name}: #{api_key}"
#     api_key
#   end

#   # ---------------------------------------------------------------
#   #  🧩 STANDARD PARTNER ADMIN ONBOARDING (Banking, Embassy, etc.)
#   # ---------------------------------------------------------------
#   def onboard_partner_admin!
#     user = User.find_or_initialize_by(email: @partner.email)

#     user.assign_attributes(
#       first_name: @partner.contact_person.presence || "Partner",
#       last_name:  "Admin",
#       partner_id: @partner.id
#     )

#     if user.new_record? || user.encrypted_password.blank?
#       tmp = SecureRandom.hex(12)
#       user.password = user.password_confirmation = tmp
#     end

#     user.save!
#     user.add_role(:partner_admin)
#     send_invite_email(user, :partner_admin)
#   rescue ActiveRecord::RecordInvalid => e
#     Rails.logger.error "🚨 onboard_partner_admin! failed: #{e.record.errors.full_messages.join(', ')}"
#     raise ActiveRecord::Rollback
#   end

#   # ---------------------------------------------------------------
#   #  🧍‍♂️ DEFAULT TELLER / AGENT FOR BANKING PARTNERS
#   # ---------------------------------------------------------------
#   def create_default_teller_agent!
#     return unless @partner.sector == "banking"

#     agent_email = "agent@#{@partner.slug}.ht"
#     agent = User.find_or_initialize_by(email: agent_email)

#     agent.assign_attributes(
#       first_name: "Default",
#       last_name:  "Agent",
#       partner_id: @partner.id
#     )

#     if agent.new_record? || agent.encrypted_password.blank?
#       tmp_pass = "Teller123!"
#       agent.password = agent.password_confirmation = tmp_pass
#     end

#     agent.save!
#     agent.add_role(:partner_agent)

#     Rails.logger.info "🧾 Created default teller agent for #{@partner.name}: #{agent.email}"
#   rescue => e
#     Rails.logger.error "🚨 create_default_teller_agent! failed: #{e.class}: #{e.message}"
#     raise ActiveRecord::Rollback
#   end

#   # ---------------------------------------------------------------
#   #  👮‍♂️ LAW ENFORCEMENT ADMIN ACCOUNT CREATION
#   # ---------------------------------------------------------------
#   def setup_officer_admin_account!
#     user = User.find_or_initialize_by(email: @partner.email)

#     user.assign_attributes(
#       first_name: @partner.contact_person.presence || "Officer",
#       last_name:  @partner.name.presence || "Admin",
#       partner_id: @partner.id
#     )

#     if user.new_record? || user.encrypted_password.blank?
#       tmp = SecureRandom.hex(12)
#       user.password = user.password_confirmation = tmp
#     end

#     user.save!
#     user.add_role(:officer)
#     user.add_role(:partner_admin)

#     officer = user.officer || user.build_officer(partner: @partner)
#     officer.assign_attributes(
#       first_name: user.first_name,
#       last_name:  user.last_name,
#       partner:    @partner,
#       unit_type:  resolve_unit_type,
#       unit_name:  resolve_unit_name
#     )
#     officer.save!

#     send_invite_email(user, :officer)
#   rescue => e
#     Rails.logger.error "🚨 setup_officer_admin_account! failed: #{e.class}: #{e.message}"
#     raise ActiveRecord::Rollback
#   end

#   # ---------------------------------------------------------------
#   #  ✉️ EMAIL HANDLING / RESET TOKEN GENERATION
#   # ---------------------------------------------------------------
#   def send_invite_email(user, role)
#     raw_token, hashed_token = Devise.token_generator.generate(User, :reset_password_token)
#     user.update!(reset_password_token: hashed_token, reset_password_sent_at: Time.current)

#     invite_url =
#       case role
#       when :partner_admin
#         edit_partner_admin_password_url(reset_password_token: raw_token, host: ENV.fetch("APP_HOST", "localhost:3000"))
#       when :officer
#         edit_officer_password_url(reset_password_token: raw_token, host: ENV.fetch("APP_HOST", "localhost:3000"))
#       end

#     Admin::PartnerAdminMailer.invite(
#       partner: @partner,
#       email:   user.email,
#       invite_url: invite_url
#     ).deliver_later
#   rescue => e
#     Rails.logger.error "🚨 send_invite_email failed: #{e.class}: #{e.message}"
#     raise ActiveRecord::Rollback
#   end

#   # ---------------------------------------------------------------
#   #  🧱 LAW ENFORCEMENT HELPERS
#   # ---------------------------------------------------------------
#   def resolve_unit_type
#     @partner.try(:unit_type).presence || "CIMO"
#   end

#   def resolve_unit_name
#     @partner.try(:unit_name).presence || "Direction Générale"
#   end
# end


# class PartnerSetupService
#     @curren_admin_user = curren_admin_user
#   end

#   def approve!
#     ActiveRecord::Base.transaction do
#       # Mark application approved

#       # Create or link Partner
#         admin_user_id: @curren_admin_user.id,
#         verified_at: Time.current
#       )

#       partner.update!(verified_at: Time.current) if partner.verified_at.blank?
#       attach_logo!(partner)

#       # Save back-reference

#       # === Role-specific handling ===
#       if partner.sector == "law_enforcement"
#         create_or_update_officer!(partner)
#       else
#         create_or_update_partner_admin!(partner)
#       end
#     end
#   end

#   private

#   def attach_logo!(partner)

#       partner.logo.attach(
#         io: tempfile, # 👈 use tempfile directly
#       )
#     end
#   end


#   def create_or_update_partner_admin!(partner)
#     user.assign_attributes(
#       last_name: "Partner Admin",
#       role_int: :partner_admin,
#       partner_id: partner.id
#     )
#     user.skip_confirmation!

#     if user.save(validate: false)
#       # ✅ Partner Admin reset password email
#       token = user.send_reset_password_instructions
#       Partner::ApplicationMailer.approved(partner).deliver_later
#       Rails.logger.info "📩 Partner Admin invite sent to #{user.email} with token #{token}"
#     else
#       raise ActiveRecord::RecordInvalid, user
#     end
#   end

#   def create_or_update_officer!(partner)
#     officer.assign_attributes(
#       last_name: "Officer",
#       role_int: :officer
#     )
#     officer.skip_confirmation!

#     if officer.save(validate: false)
#       # ✅ Officer reset password email
#       token = officer.send_reset_password_instructions
#       OfficerMailer.invitation_email(officer, token).deliver_later
#       Rails.logger.info "📩 Officer invite sent to #{officer.email} with token #{token}"
#     else
#       raise ActiveRecord::RecordInvalid, officer
#     end
#   end
# end
