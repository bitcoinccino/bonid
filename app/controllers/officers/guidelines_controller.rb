# app/controllers/officers/guidelines_controller.rb
# frozen_string_literal: true

module Officers
  class GuidelinesController < BaseController
    # Guidelines is a gate page — use the minimal officers_gate layout:
    # full-viewport, no sidebar, no navbar, no two-column grid.
    layout "officers_gate"

    skip_before_action :ensure_guidelines_confirmed, only: [:index, :confirm]

    def index
      @guidelines = guidelines
      @legal_warnings = legal_warnings
    end

    def confirm
      if params[:confirmed] == "1"
        now = Time.current

        # guidelines_confirmed_at lives on the users table — persist via the associated user
        current_officer.user&.update_column(:guidelines_confirmed_at, now)

        # Write immutable audit trail — description column holds JSON (no metadata column on audit_logs)
        AuditLog.create!(
          record_type: "Officer",
          record_id:   current_officer.id,
          officer_id:  current_officer.id,
          badge_id:    current_officer.badge_id,
          action:      "guidelines_confirmed",
          description: {
            confirmed_at: now.iso8601,
            ip:           request.remote_ip,
            user_agent:   request.user_agent.to_s.first(200)
          }.to_json,
          created_at:  now
        )

        # Session cache — avoids a DB hit on every subsequent request
        session[:officer_guidelines_confirmed]    = true
        session[:officer_guidelines_confirmed_at] = now.to_s

        redirect_to officers_dashboard_path, notice: "✅ Directives confirmées. Bienvenue, Officier."
      else
        redirect_to officers_guidelines_path, alert: "Veuillez cocher la case pour confirmer avant de continuer."
      end
    end

    private

    # Officer-specific guidelines emphasizing integrity, legal responsibility, and ethical conduct
    def guidelines
      [
        # Oath & Service Commitment
        {
          category: "Serment et Engagement",
          icon: "ri-shield-star-line",
          items: [
            "Je suis officier de la Police Nationale d'Haïti (PNH). J'ai choisi de servir et protéger le peuple haïtien.",
            "Mon devoir est d'appliquer la loi avec intégrité, impartialité et respect des droits de chaque citoyen.",
            "Je représente l'État haïtien. Mes actions reflètent l'honneur de la PNH et la confiance du peuple."
          ]
        },
        # Data Integrity & Legal Consequences
        {
          category: "Intégrité des Données",
          icon: "ri-database-2-line",
          items: [
            "Les données saisies dans ce système seront utilisées comme preuves devant les tribunaux haïtiens.",
            "Toute falsification, manipulation ou saisie de fausses informations constitue un délit pénal.",
            "Je dois vérifier visuellement l'identité de chaque personne avant d'enregistrer ses informations.",
            "Je ne dois jamais créer de faux rapports d'incident ou impliquer des personnes innocentes."
          ]
        },
        # Protection of Citizen & Tourist Data
        {
          category: "Protection des Données",
          icon: "ri-lock-line",
          items: [
            "Les données BonID et BonTouris sont strictement confidentielles et protégées par la loi.",
            "Je ne dois jamais partager, copier ou divulguer ces données à des personnes non autorisées.",
            "L'utilisation de ces données à des fins personnelles, commerciales ou de corruption est interdite.",
            "Je dois signaler immédiatement toute tentative d'accès non autorisé ou de corruption."
          ]
        },
        # Accountability & Audit Trail
        {
          category: "Traçabilité et Responsabilité",
          icon: "ri-eye-line",
          items: [
            "Toutes mes actions sont enregistrées et peuvent être auditées par mes supérieurs.",
            "Chaque scan, recherche et rapport est lié à mon identité d'officier.",
            "Je suis personnellement responsable de l'exactitude des informations que je saisis.",
            "Les rapports falsifiés peuvent entraîner la révocation, des poursuites pénales et l'emprisonnement."
          ]
        }
      ]
    end

    # Legal warnings - general principles without citing specific articles
    def legal_warnings
      [
        {
          title: "Falsification de Documents Officiels",
          description: "La falsification de rapports d'incident ou de données d'identité constitue un délit pénal passible de poursuites criminelles et d'emprisonnement.",
          severity: "danger"
        },
        {
          title: "Abus de Fonction",
          description: "L'utilisation abusive de votre autorité ou l'accès non autorisé aux données personnelles des citoyens entraîne des sanctions pénales.",
          severity: "danger"
        },
        {
          title: "Confidentialité des Données",
          description: "La divulgation non autorisée de données BonID/BonTouris à des tiers est interdite et passible de sanctions disciplinaires et légales.",
          severity: "warning"
        },
        {
          title: "Règlement Intérieur de la PNH",
          description: "Les violations éthiques entraînent la suspension immédiate, la révocation et des poursuites disciplinaires selon les procédures de la Police Nationale d'Haïti.",
          severity: "warning"
        }
      ]
    end
  end
end
