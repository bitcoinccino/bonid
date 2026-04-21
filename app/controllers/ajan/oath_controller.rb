# frozen_string_literal: true

# Ajan::OathController
# ====================
# Gates the Agent Portal behind a signed oath. Every ajan must read and
# acknowledge the oath (one confirmation box + submit) before the Tablo
# becomes accessible. The acceptance is stamped on User with a version
# string; bumping CURRENT_VERSION forces every agent to re-accept on
# their next login.
#
# Mirrors partner_portal/guidelines_acceptance_controller.rb but scoped
# per-agent (not per-partner), since every individual agent is expected
# to read and sign.
module Ajan
  class OathController < Ajan::ApplicationController
    skip_before_action :ensure_oath_accepted!

    # Use a minimal full-screen layout so the ajan reads the oath before any
    # partner chrome (sidebar / navbar) appears. Same pattern as partner_portal
    # guidelines_acceptance_controller → "partner_portal/public".
    layout "partner_portal/public"

    CURRENT_VERSION = "v1"

    # GET /ajan/serman
    def index
      # If the agent already signed the oath in THIS session, send them
      # straight to Tablo. (Acceptance is session-scoped — every new login
      # re-prompts.)
      if session[:ajan_oath_accepted_version] == CURRENT_VERSION
        redirect_to ajan_tablo_path, notice: "Ou deja siyen sèman an pou sesyon sa a."
        return
      end

      @agent            = current_agent
      @partner          = current_partner
      @version          = CURRENT_VERSION
      @oath_items       = oath_items
      @bonid_submission = current_agent&.verified_identity_submission
    end

    # POST /ajan/serman
    def accept
      unless params[:confirmed] == "1"
        redirect_to ajan_oath_path,
                    alert: "Tanpri tcheke bwat la pou konfime ou li ak aksepte sèman an."
        return
      end

      # Gate for THIS session only — next login clears the session and the
      # agent must re-sign. Persist the columns too so admins have an audit
      # trail of the most recent acceptance timestamp + version.
      session[:ajan_oath_accepted_version] = CURRENT_VERSION

      current_agent.update!(
        ajan_oath_accepted_at: Time.current,
        ajan_oath_version:     CURRENT_VERSION
      )

      # Audit on the agent's partner so admins can see who accepted and when.
      if current_partner.present?
        PartnerAuditLog.log!(
          current_partner,
          current_agent,
          "ajan_oath_accepted",
          {
            version:    CURRENT_VERSION,
            agent_id:   current_agent.id,
            agent_name: current_agent.full_name,
            ip_address: request.remote_ip,
            user_agent: request.user_agent
          }
        )
      end

      redirect_to ajan_tablo_path,
                  notice: "✅ Sèman an siyen. Byenveni nan Pòtay Ajan."
    end

    private

    # Shared accordion format — mirrors citizens/election/vote/oath.html.erb:
    # each card has a summary, an icon/color, and a list of bullet points
    # (items) surfaced with check-icons in the body.
    def oath_items
      [
        {
          key:     "entegrite",
          title:   "Entegrite ak Onètete",
          summary: "Chak verifikasyon fèt ak bon konsyans, san fwod ni favè",
          icon:    "ri-shield-check-line",
          color:   "#1D4ED8",
          items:   [
            { icon: "ri-checkbox-circle-line", text: "Mwen p ap janm <strong>falsifye yon eskanè</strong> ni valide yon idantite ki pa bon." },
            { icon: "ri-money-dollar-circle-line", text: "Mwen p ap <strong>aksepte lajan</strong> oswa okenn lòt avantaj pou m tronpe sistèm nan." },
            { icon: "ri-user-follow-line", text: "Mwen konfime se <strong>mwen menm sèlman</strong> kap itilize kont ajan sa a, mwen p ap pataje l ak lòt moun." }
          ]
        },
        {
          key:     "done_prive",
          title:   "Konfidansyalite Done",
          summary: "Enfòmasyon sitwayen yo rete nan sistèm nan, pa deyò",
          icon:    "ri-file-lock-line",
          color:   "#059669",
          items:   [
            { icon: "ri-eye-off-line", text: "Mwen p ap <strong>pataje oswa fotografye</strong> okenn enfòmasyon idantite andeyò Pòtay Ajan an." },
            { icon: "ri-database-2-line", text: "Mwen p ap <strong>estoke done</strong> sitwayen yo sou telefòn, kanè, oswa nenpòt lòt sistèm pèsonèl." },
            { icon: "ri-lock-2-line", text: "Mwen ap <strong>dekonekte kont mwen</strong> chak fwa mwen kite machin nan, pou pesòn pa ka antre nan non mwen." }
          ]
        },
        {
          key:     "respe",
          title:   "Respè ak Diyite",
          summary: "Chak sitwayen resevwa menm sèvis, menm respè",
          icon:    "ri-hand-heart-line",
          color:   "#7C3AED",
          items:   [
            { icon: "ri-equalizer-line", text: "Mwen ap trete chak sitwayen <strong>san diskriminasyon</strong> sou baz ras, sèks, relijyon, laj, oswa lokalite." },
            { icon: "ri-customer-service-2-line", text: "Mwen ap kenbe <strong>yon langaj respè</strong> ak pwofesyonalite, menm nan sitiyasyon difisil." },
            { icon: "ri-accessibility-line", text: "Mwen ap bay <strong>èd adapte</strong> pou moun aje, moun ak andikap, oswa moun ki poko abitye ak teknoloji." }
          ]
        },
        {
          key:     "rapo",
          title:   "Rapò Ensidan",
          summary: "Tout fwod oswa pwoblèm rapòte imedyatman",
          icon:    "ri-alarm-warning-line",
          color:   "#B91C1C",
          items:   [
            { icon: "ri-spy-line", text: "Mwen ap <strong>rapòte tou swit</strong> tout tantativ fwòd oswa manipilasyon nan sistèm nan." },
            { icon: "ri-error-warning-line", text: "Mwen ap <strong>siyale</strong> nenpòt mal fonksyònman oswa bug bay administratè patnè mwen an." },
            { icon: "ri-message-3-line", text: "Mwen p ap <strong>kache enfòmasyon</strong> sou yon kòlèg ki pa swiv règ yo — silans ap pwoteje fwod." }
          ]
        },
        {
          key:     "lwa",
          title:   "Konsekans Legal",
          summary: "Chak aksyon anrejistre, chak fwod gen konsekans",
          icon:    "ri-scales-3-line",
          color:   "#B45309",
          items:   [
            { icon: "ri-file-search-line", text: "Chak aksyon mwen fè nan Pòtay Ajan an <strong>anrejistre nan yon jounal odit</strong> ki ka sèvi kòm prèv devan tribinal." },
            { icon: "ri-building-4-line", text: "<strong>Sivil.</strong> Revokasyon aksè, pèt kontra ajan, ak amann selon lwa travay yo." },
            { icon: "ri-scales-2-line", text: "<strong>Kriminèl.</strong> Pousuit devan tribinal dapre Kòd Penal ayisyen pou fwod idantite oswa abi konfyans." },
            { icon: "ri-quill-pen-line", text: "Siyen mwen anba a gen menm valè legal ak yon <strong>sèman ekri devan patnè mwen an ak BonID</strong>." }
          ]
        }
      ]
    end
  end
end
