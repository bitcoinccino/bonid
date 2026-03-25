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
  after_update_commit :track_status_change, if: :saved_change_to_status?

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

    # Create partner audit entry for transparency
    PartnerAuditLog.create!(
      partner: partner,
      event: "consent_revoked",
      details: "Citizen revoked consent (#{citizen.email})",
      metadata: { grant_id: id, reason: reason }
    )
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
