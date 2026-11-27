# frozen_string_literal: true

class ConsentGrant < ApplicationRecord
  belongs_to :citizen, class_name: "User"
  belongs_to :partner

  # ======================================================
  # 🔢 Status Enum
  # ======================================================
  enum :status, {
    pending: 0,
    approved: 1,
    revoked: 2,
    expired: 3
  }

  # ======================================================
  # ✅ Validations
  # ======================================================
  validates :grant_token, presence: true, uniqueness: true
  validates :requested_scopes, presence: true
  validates :partner_id, uniqueness: { scope: :citizen_id }, on: :dashboard

  # ======================================================
  # 🧠 Lifecycle Hooks
  # ======================================================
  before_validation :generate_grant_token, on: :create
  before_save :expire_if_due
  # Remember the status change at save time: other commit callbacks
  # (track_status_change → append_audit!) save again before this runs, which
  # would wipe saved_change_to_status.
  after_save :remember_status_transition, if: :saved_change_to_status?
  after_update_commit :track_status_change, if: :saved_change_to_status?
  # One after_commit (not after_create_commit + after_update_commit with the
  # same method — Rails keeps only the last of those, so creates were missed).
  # Runs before email_citizen_about_access (callbacks run in the order
  # defined), so @status_transition is still set here.
  after_commit :broadcast_alert_to_citizen, on: %i[create update],
               if: -> { previously_new_record? || @status_transition.present? }

  def broadcast_alert_to_citizen
    Citizens::AlertBroadcastJob.perform_later(citizen_id) if citizen_id
  end

  # Email the citizen when a partner starts or stops seeing their information.
  # Lives on the model so every path (dashboard, OAuth sign-in, API) sends it.
  # A declined *pending* request is not a removal, so it sends nothing.
  after_commit :email_citizen_about_access, on: %i[create update]

  def remember_status_transition
    @status_transition = saved_change_to_status
  end

  def email_citizen_about_access
    from, to = @status_transition
    @status_transition = nil
    return if to.nil?

    if to.to_s == "approved" && from.to_s != "approved"
      Citizens::AccessMailer.with(grant: self).access_granted.deliver_later
    elsif to.to_s == "revoked" && from.to_s == "approved"
      Citizens::AccessMailer.with(grant: self).access_removed.deliver_later
    end
  rescue => e
    Rails.logger.error("[ConsentGrant##{id}] access email failed: #{e.class}: #{e.message}")
  end

  # ======================================================
  # 🔍 Scopes
  # ======================================================
  scope :active, -> { where(status: :approved).where("expires_at > ?", Time.current) }
  scope :not_deleted, -> { where(deleted_at: nil) }

  # ======================================================
  # 🟢 Status Helper Methods
  # ======================================================
  def pending?
    status == "pending"
  end

  def approved?
    status == "approved"
  end

  def active?
    approved? && (expires_at.nil? || expires_at > Time.current)
  end

  # ======================================================
  # 🎨 Status Theme (css class + icon for UI)
  # ======================================================
  def status_theme
    case status
    when "approved" then { css: "success", icon: "ri-checkbox-circle-fill" }
    when "pending"  then { css: "warning", icon: "ri-time-fill" }
    when "revoked"  then { css: "danger",  icon: "ri-forbid-2-line" }
    else                 { css: "secondary", icon: "ri-eye-off-line" }
    end
  end

  # ======================================================
  # 📊 Record Partner Access (non-blocking, best-effort)
  # ======================================================
  def record_access!
    # update_columns skips callbacks/validations and avoids touching updated_at
    update_columns(
      last_accessed_at: Time.current,
      access_count:     access_count.to_i + 1
    )
  rescue => e
    Rails.logger.warn("[ConsentGrant#record_access!] #{e.class}: #{e.message}")
  end

  def revoked?
    status == "revoked"
  end

  def expired?
    status == "expired"
  end

  # ======================================================
  # 🟢 Approve Consent
  # ======================================================
  def grant!(scopes:)
    update!(
      granted_scopes: Array(scopes),
      status: :approved,
      granted_at: Time.current,
      expires_at: 90.days.from_now
    )
    append_audit!("granted", scopes: scopes)
  end

  # ======================================================
  # 🔴 Revoke Consent (Centralized Logic)
  # ======================================================
  def revoke!(reason: nil)
    update!(
      status: :revoked,
      revoked_at: Time.current,
      change_reason: reason,
      metadata: metadata.merge({ revoked_reason: reason }.compact)
    )

    append_audit!("revoked", reason: reason)

    # 1. Immediately invalidate all active tokens for this citizen + partner
    revoked_count = invalidate_partner_tokens!

    # 2. Create partner audit entry for transparency
    PartnerAuditLog.create!(
      partner: partner,
      event: "consent_revoked",
      details: "Citizen revoked consent (#{citizen.email}). #{revoked_count} token(s) invalidated.",
      metadata: { grant_id: id, reason: reason, tokens_revoked: revoked_count }
    )

    # 3. Fire consent.revoked webhook (async — includes data erasure request)
    ConsentWebhookJob.perform_later(id, "consent.revoked")
  end

  # ======================================================
  # 🕒 Auto-Expire When Due
  # ======================================================
  def expire_if_due
    self.status = :expired if expires_at.present? && expires_at < Time.current
  end

  # ======================================================
  # 🧾 Summary
  # ======================================================
  def summary
    {
      bonid: citizen.bonid,
      partner: partner.name,
      scopes: granted_scopes.presence || requested_scopes,
      status: status,
      granted_at: granted_at,
      expires_at: expires_at
    }
  end

  # ======================================================
  # 🧹 Soft Delete
  # ======================================================
  def soft_delete!(reason: nil)
    update!(deleted_at: Time.current, change_reason: reason)
    append_audit!("soft_delete", reason: reason)
  end

  # ======================================================
  # 🧠 Audit Trail
  # ======================================================
  def append_audit!(action, details = {})
    self.audit_log ||= {}
    self.audit_log[Time.current.iso8601] = {
      action: action,
      status: status,
      details: details,
      actor: Current.user&.id || "system"
    }
    save!(touch: false)
  end

  # ======================================================
  # 🔑 Generate Grant Token (public — called from controller)
  # ======================================================
  def generate_grant_token
    self.grant_token ||= SecureRandom.hex(16)
  end

  # ======================================================
  # 🔒 Token Invalidation (GDPR Article 17 compliance)
  # ======================================================
  def invalidate_partner_tokens!
    tokens = OauthAccessToken.where(
      partner_id: partner_id,
      citizen_id: citizen_id,
      revoked_at: nil
    ).where("expires_at > ?", Time.current)

    count = tokens.count
    tokens.update_all(revoked_at: Time.current) if count > 0

    Rails.logger.info("[ConsentGrant] Revoked #{count} active token(s) for citizen #{citizen_id} + partner #{partner.slug}")
    count
  end

  private

  # Track status changes
  def track_status_change
    append_audit!(
      "status_change",
      from: status_before_last_save,
      to: status
    )
  end
end
