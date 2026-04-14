# frozen_string_literal: true

module PartnerPortal
  class GuidelinesAcceptanceController < PartnerPortal::BaseController
    skip_before_action :ensure_guidelines_accepted!
    skip_before_action :ensure_correct_sector
    layout "partner_portal/public"

    before_action :ensure_partner_exists
    before_action :check_if_already_accepted, only: [:index]

    CURRENT_VERSION = "1.0"

    # GET /partner_portal/guidelines
    def index
      @partner = @current_partner
      @guidelines = partner_guidelines
      @version = CURRENT_VERSION
      load_bonid_signature
    end

    # POST /partner_portal/guidelines/accept
    def accept
      @partner = @current_partner

      unless params[:confirmed] == "1"
        redirect_to partner_portal_guidelines_path,
                    alert: "Tanpri tcheke bwat la pou konfime ou li ak aksepte direktiv yo."
        return
      end

      @partner.update!(
        guidelines_accepted_at: Time.current,
        guidelines_version: CURRENT_VERSION,
        guidelines_accepted_by_id: @current_portal_user&.id
      )

      # Audit log the acceptance
      PartnerAuditLog.log!(
        @partner,
        @current_portal_user,
        "guidelines_accepted",
        {
          version: CURRENT_VERSION,
          accepted_by_name: @current_portal_user&.full_name || @current_portal_user&.email,
          accepted_by_id: @current_portal_user&.id,
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        }
      )

      redirect_to partner_portal_dashboard_path,
                  notice: "✅ Direktiv yo aksepte. Ou ka itilize Portal Patnè a kounye a."
    end

    private

    def ensure_partner_exists
      unless @current_partner
        redirect_to root_path, alert: "No partner profile found."
      end
    end

    def check_if_already_accepted
      if guidelines_accepted?(@current_partner)
        redirect_to partner_portal_dashboard_path,
                    notice: "Ou deja aksepte direktiv yo."
      end
    end

    def guidelines_accepted?(partner)
      return false unless partner.present?

      partner.guidelines_accepted_at.present? &&
        partner.guidelines_version == CURRENT_VERSION
    end

    # Load the partner admin's BonID signature from their verified identity submission
    def load_bonid_signature
      submission = @current_portal_user&.verified_identity_submission
      if submission&.signature&.attached?
        @bonid_signature = submission.signature
        @signature_available = true
      else
        @signature_available = false
      end
    end

    # Partner-specific guidelines — structured with icons and summaries for card UI
    def partner_guidelines
      [
        {
          key: "sekirite",
          title: "Sekirite Done",
          icon: "ri-shield-check-line",
          color: "#0d132d",
          summary: "Pwoteje done itilizatè ak chifre, MFA, ak aksè limite.",
          items: [
            "Chifre done itilizatè pandan estokaj ak transmisyon pou anpeche aksè san otorizasyon.",
            "Aksede done itilizatè sèlman pou rezon otorize, tankou <strong>verifikasyon</strong> oswa <strong>sipò</strong>.",
            "Limite retansyon done nan <strong>peryòd minimòm</strong> ki nesesè dapre pwotokòl BonID.",
            "Aplike <strong>otantifikasyon milti-faktè (MFA)</strong> pou tout aksè admin nan sistèm sansib yo."
          ]
        },
        {
          key: "konfidansyalite",
          title: "Konfidansyalite ak Konformite",
          icon: "ri-file-lock-line",
          color: "#198754",
          summary: "Respekte lwa pwoteksyon done Ayiti ak estanda entènasyonal.",
          items: [
            "Pa pataje done itilizatè ak <strong>twazyèm pati</strong> san konsantman klè.",
            "Respekte règleman pwoteksyon done Ayiti ak estanda entènasyonal (tankou <strong>prensip GDPR</strong>).",
            "Pèmèt itilizatè yo <strong>revoke konsantman</strong> epi efase done yo nenpòt lè.",
            "Fè evalyasyon enpak sou vi prive pou nouvo fonksyonalite ki enplike done idantite."
          ]
        },
        {
          key: "etik",
          title: "Itilizasyon Etik ak Responsablite",
          icon: "ri-hand-heart-line",
          color: "#6f42c1",
          summary: "Asire transparans, odit, ak fòmasyon anplwaye.",
          items: [
            "Itilize jounal eskanè BonID pou <strong>odit verifikasyon idantite</strong> epi asire responsablite.",
            "Rapòte tout vyolasyon done oswa aktivite sispèk bay ekip sekirite BonID <strong>imedyatman</strong>.",
            "Redui biyè nan pwosesis verifikasyon lè w revize algoritm ak done fòmasyon regilyèman.",
            "Fòme anplwaye sou pratik etik pou jere done pou kenbe konfyans itilizatè."
          ]
        },
        {
          key: "ensidan",
          title: "Repons Ensidan ak Mizajou",
          icon: "ri-alarm-warning-line",
          color: "#dc3545",
          summary: "Rapòte ensidan nan 24è, patisipe nan odit anyèl.",
          items: [
            "Devlope epi teste plan repons ensidan pou evènman sekirite done.",
            "Rete ajou sou lwa konfidansyalite k ap evolye epi mete direktiv yo ajou an konsekans.",
            "Notifye BonID nan <strong>24è</strong> apre nenpòt ensidan sekirite ki afekte done itilizatè.",
            "Patisipe nan <strong>odit sekirite anyèl</strong> BonID mande yo."
          ]
        },
        {
          key: "api",
          title: "Itilizasyon API ak Entegrasyon",
          icon: "ri-code-box-line",
          color: "#fd7e14",
          summary: "Jere kle API an sekirite, respekte limit debiman.",
          items: [
            "<strong>Pa janm</strong> estoke kle API nan kòd sous oswa depo piblik.",
            "Itilize sèlman pwen bout API otorize epi respekte <strong>limit debiman</strong> yo.",
            "Dokimante tout entegrasyon ak pataje dokiman ak ekip BonID.",
            "Retire aksè <strong>imedyatman</strong> lè yon anplwaye kite òganizasyon an."
          ]
        }
      ]
    end
  end
end
