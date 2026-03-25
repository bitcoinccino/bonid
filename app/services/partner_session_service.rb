# frozen_string_literal: true

# app/services/partner_session_service.rb
#
# Responsible for storing and managing the currently active partner
# context (slug, ID, sector, etc.) across web + OTP sessions.
# Must always be instantiated with both `session` and `params`.
#
# ✅ Correct usage:
#   PartnerSessionService.new(session, params).store!

class PartnerSessionService
  attr_reader :session, :params

  def initialize(session, params)
    raise ArgumentError, "session and params are required" unless session && params

    @session = session
    @params  = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h.symbolize_keys : params.symbolize_keys
  end

  # ================================================================
  # Store partner context in session (used across portals & OTP flow)
  # ================================================================
  def store!
    slug = detect_slug
    return unless slug.present?

    partner = Partner.find_by(slug: slug)

    unless partner&.verified_at.present?
      Rails.logger.warn "⚠️ [PartnerSessionService] Invalid or unverified partner slug: #{slug}"
      clear_session!
      return
    end

    persist_session!(partner)
    Rails.logger.info "🏦 [PartnerSessionService] Partner session stored: #{partner.name} (#{partner.sector})"
  rescue => e
    Rails.logger.error "❌ [PartnerSessionService] store! failed: #{e.class} – #{e.message}"
    Rails.logger.error e.backtrace.take(5).join("\n")
    clear_session!
  end

  # ================================================================
  # Helpers
  # ================================================================
  def current_partner
    return nil unless session[:partner_slug]
    Partner.find_by(slug: session[:partner_slug])
  rescue => e
    Rails.logger.error "[PartnerSessionService] current_partner lookup failed: #{e.message}"
    nil
  end

  def clear_session!
    %i[bonid_partner_id partner_slug partner_context login_source].each { |key| session.delete(key) }
  end

  private

  # Detect slug param from any allowed key
  def detect_slug
    slug = params[:partner_slug] || params[:partner] || params[:slug]
    slug.is_a?(String) ? slug.strip.downcase : nil
  end

  # Save all relevant partner info into the session
  def persist_session!(partner)
    session[:bonid_partner_id] = partner.id
    session[:partner_slug]     = partner.slug
    session[:partner_context]  = {
      id:       partner.id,
      slug:     partner.slug,
      name:     partner.name,
      sector:   partner.sector,
      verified: partner.verified_at.present?,
      source:   "partner:#{partner.slug}"
    }
    session[:login_source] = "partner:#{partner.slug}"
  end
end
