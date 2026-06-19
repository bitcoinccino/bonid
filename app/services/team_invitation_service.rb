# frozen_string_literal: true

# TeamInvitationService
# =====================
# Unified team invitation flow for ALL partner sectors except PNH/law enforcement.
#
# Universal rule: every invitee MUST have a verified BonID.
# Lookup by last 6 chars of BonID (no dashes) — name + email pulled from verified record.
#
# Roles come from GovernmentRoleConstants — sector-specific.
# Base: partner_admin, partner_agent, partner_supervisor
# ONACA: partner_admin, partner_agent_surveyor, partner_agent_notary, partner_supervisor
#
# Usage:
#   result = TeamInvitationService.call(
#     partner:     partner,
#     bonid:       "A3FB2C",              # last 6 chars, no dashes
#     role:        "partner_agent",       # role key from GovernmentRoleConstants
#     invited_by:  current_user,
#     employee_id: "DGI-EMP-0042",        # optional, partner admin provides
#     office_code: "Bureau Central PAP"   # optional, partner admin provides
#   )

class TeamInvitationService
  Result = Struct.new(:success?, :user, :error, keyword_init: true)

  def self.call(**args)
    new(**args).call
  end

  def initialize(partner:, bonid:, role:, invited_by:, employee_id: nil, office_code: nil)
    @partner     = partner
    @bonid       = bonid.to_s.strip.delete("-").upcase
    @role        = role.to_s
    @invited_by  = invited_by
    @employee_id = employee_id.to_s.strip.presence
    @office_code = office_code.to_s.strip.presence
  end

  def call
    return failure("BonID obligatwa.") if @bonid.blank?
    return failure("Wòl obligatwa.")   if @role.blank?

    # Validate role is valid for this partner's sector
    sector = partner_sector
    valid_keys = GovernmentRoleConstants.valid_role_keys_for(sector)
    unless valid_keys.include?(@role)
      return failure("Wòl \"#{@role}\" pa valid pou sektè sa a.")
    end

    # ============================================================
    # LOOKUP: Find user by last 6 characters of BonID
    # ============================================================
    user = self.class.find_by_suffix(@bonid)

    return failure(
      "Pa gen moun ak BonID ki fini ak \"#{@bonid}\". Verifye kòd la epi eseye ankò."
    ) unless user

    # ============================================================
    # GATE: Must have verified (approved) identity submission
    # ============================================================
    unless user.identity_submissions.approved.exists?
      return failure(
        "#{user.full_name} gen yon kont BonID men li poko verifye. Yo dwe gen yon BonID apwouve anvan yo ka jwenn envitasyon."
      )
    end

    # ============================================================
    # GATE: Already on this team with same role
    # ============================================================
    if user.partner_id == @partner.id && user.has_role?(@role)
      label = GovernmentRoleConstants.role_label(sector, @role)
      return failure("#{user.full_name} deja nan ekip ou kòm #{label}.")
    end

    # ============================================================
    # GATE: Cannot invite yourself
    # ============================================================
    return failure("Ou pa ka envite tèt ou.") if user.id == @invited_by.id

    # ============================================================
    # ASSIGN: Role + partner association
    # ============================================================
    ActiveRecord::Base.transaction do
      user.add_role(@role) unless user.has_role?(@role)
      user.update!(partner_id: @partner.id) unless user.partner_id == @partner.id

      # Generate invitation token (Devise invitable)
      raw_token, digested_token = Devise.token_generator.generate(User, :invitation_token)
      user.update!(
        invitation_token:      digested_token,
        invitation_created_at: Time.current,
        invitation_sent_at:    Time.current,
        invited_by:            @invited_by
      )

      # Send invitation to the VERIFIED email only
      TeamMailer.invitation(
        user:    user,
        partner: @partner,
        role:    @role,
        token:   raw_token
      ).deliver_later

      # Audit trail
      PartnerAuditLog.create!(
        partner:    @partner,
        event:      "team_invitation_sent",
        details: {
          invited_by:    @invited_by.full_name,
          invited_by_id: @invited_by.id,
          invitee_email: user.email,
          invitee_name:  user.full_name,
          invitee_bonid: user.bonid,
          role:          @role,
          role_label:    GovernmentRoleConstants.role_label(sector, @role),
          employee_id:   @employee_id,
          office_code:   @office_code,
          sector:        sector,
          ip:            Current.request&.ip
        }
      )
    end

    Result.new(success?: true, user: user)
  rescue ActiveRecord::RecordInvalid => e
    failure("Erè baz done: #{e.record.errors.full_messages.join(', ')}")
  rescue => e
    Rails.logger.error "[TeamInvitationService] #{e.class}: #{e.message}"
    failure("Yon erè te rive. Tanpri eseye ankò.")
  end

  # === LOOKUP (for the form preview) ===
  def self.lookup(bonid_suffix)
    suffix = bonid_suffix.to_s.strip.delete("-").upcase
    return nil if suffix.blank?

    user = find_by_suffix(suffix)
    return nil unless user

    {
      bonid:     user.bonid,
      full_name: user.full_name,
      email:     mask_email(user.email),
      photo_url: (Rails.application.routes.url_helpers.url_for(user.photo) if user.photo.attached?),
      verified:  user.identity_submissions.approved.exists?
    }
  rescue
    nil
  end

  # Find user by last 6 chars of BonID (stripped of dashes)
  def self.find_by_suffix(suffix)
    cleaned = suffix.delete("-")
    User.where("REPLACE(UPPER(bonid), '-', '') LIKE ?", "%#{cleaned}").first
  end

  # Search by email OR BonID (unique identifiers — no fuzzy name matching).
  # Only returns CITIZENS with a verified BonID; excludes partner/system admins.
  # Returns up to `limit` matches.
  def self.search(query, limit: 12)
    q = query.to_s.strip
    return User.none if q.blank?

    suffix    = q.delete("-").upcase
    admin_ids = (User.with_role(:partner_admin).ids + User.with_role(:admin_user).ids).uniq

    User
      .where(id: IdentitySubmission.approved.select(:user_id)) # verified BonID only
      .where.not(id: admin_ids)                                # not a partner/system admin
      .where("email ILIKE :q OR REPLACE(UPPER(bonid), '-', '') LIKE :suffix",
             q: "%#{q}%", suffix: "%#{suffix}")
      .limit(limit)
  end

  # Profile hash used by the invite UI (photo, name, masked email, verified flag).
  def self.profile(user)
    return nil unless user
    {
      bonid:     user.bonid,
      full_name: user.full_name,
      email:     mask_email(user.email),
      photo_url: (Rails.application.routes.url_helpers.url_for(user.photo) if user.photo.attached?),
      verified:  user.identity_submissions.approved.exists?
    }
  rescue
    nil
  end

  def self.mask_email(email)
    return nil if email.blank?
    local, domain = email.split("@")
    return email if local.length <= 2
    "#{local[0..1]}#{'*' * [ local.length - 2, 4 ].min}@#{domain}"
  end

  private

  def failure(msg)
    Result.new(success?: false, error: msg)
  end

  def partner_sector
    (@partner.department_sector || @partner.sector).to_s.downcase
  end
end
