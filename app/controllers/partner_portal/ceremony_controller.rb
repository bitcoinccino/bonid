# frozen_string_literal: true

module PartnerPortal
  # CEP decryption-key ceremony — generation and one-time printable
  # distribution. The submission/reconstruct side of the ceremony is
  # handled by the existing Election::MultiSigService and the dashboard
  # multi-sig surface; this controller is strictly the
  # generate-and-distribute step.
  #
  # Flow:
  #
  #   GET  /partner_portal/election/:election_id/ceremony
  #        → status: are shards generated yet? how many distributed?
  #
  #   POST /partner_portal/election/:election_id/ceremony/generate
  #        → mints master key, splits 5-of-9, mints per-shard X25519
  #          keypairs, seals shares into envelopes, persists wires +
  #          recipient public keys, and renders the ONE-TIME printable
  #          page directly. Recipient private keys + QR backups exist
  #          ONLY in this response — no GET fetches them later.
  #
  # Authorization: CEP sector + partner_admin role. Mirrors
  # DiplomaticMissionsController#ensure_cep_sector!.
  class CeremonyController < PartnerPortal::BaseController
    before_action :ensure_cep_sector!
    before_action :require_partner_admin!
    before_action :set_election

    # GET /partner_portal/election/:election_id/ceremony
    def show
      @generated = @election.decryption_key_generated?
      @shards    = @election.election_key_shards.order(:role)
    end

    # POST /partner_portal/election/:election_id/ceremony/generate
    #
    # Mints + seals + immediately renders the printable bundle. Uses
    # `regenerate_with_envelopes!` if the caller passes `force=true`
    # (every prior printed envelope becomes worthless).
    def generate
      service = ::Election::DecryptionKeyCeremonyService.new(@election)

      result =
        if ActiveModel::Type::Boolean.new.cast(params[:force])
          service.regenerate_with_envelopes!
        else
          service.generate_with_envelopes!
        end

      @shards    = result[:rows]
      @printable = result[:printable]
      audit!("decryption_keys.generated",
             count:           @shards.size,
             regenerated:     params[:force].present?,
             fingerprint16:   @election.decryption_key_fingerprint.to_s[0, 16])

      # No layout: this page is for printing; no chrome, no nav.
      render :printable, layout: false
    rescue ::Election::DecryptionKeyCeremonyService::AlreadyGeneratedError => e
      redirect_to partner_portal_election_ceremony_path(@election),
                  alert: e.message
    rescue ::Election::DecryptionKeyCeremonyService::GenerationError => e
      Rails.logger.error("[Ceremony] generation failed: #{e.message}")
      redirect_to partner_portal_election_ceremony_path(@election),
                  alert: "Jenerasyon kle echwe: #{e.message}"
    end

    private

    def set_election
      @election = BonvoteElection.find(params[:election_id])
    rescue ActiveRecord::RecordNotFound
      redirect_to partner_portal_dashboard_path,
                  alert: "Eleksyon pa jwenn." and return
    end

    # CEP-only surface (mirrors DiplomaticMissionsController).
    def ensure_cep_sector!
      sector = (@current_partner.department_sector || @current_partner.sector).to_s.downcase
      return if sector == "cep"
      redirect_to partner_portal_dashboard_path,
                  alert: "Aksè refize. Sèlman patnè CEP ka jere seremoni dechifraj."
    end

    def require_partner_admin!
      return if current_portal_user&.has_role?(:partner_admin)
      redirect_to partner_portal_dashboard_path,
                  alert: "Sèlman administratè CEP ka deklanche jenerasyon kle."
    end

    def audit!(event, extra = {})
      PartnerAuditLog.log!(@current_partner, current_portal_user, event,
                           { election_id: @election&.id,
                             ip_address:  request.remote_ip,
                             user_agent:  request.user_agent }.merge(extra))
    rescue => e
      Rails.logger.warn("[Ceremony] audit log failed for #{event}: #{e.message}")
    end
  end
end
