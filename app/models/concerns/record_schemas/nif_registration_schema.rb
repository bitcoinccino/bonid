# frozen_string_literal: true

# BonID — NIF Registration Schema (Formulaire A - Personne Physique)
# ===================================================================
# Gateway form: every citizen needs a NIF before any other DGI form.
# Links the citizen's BonID to their NIF permanently.
# ===================================================================

module RecordSchemas
  module NifRegistrationSchema
    extend ActiveSupport::Concern

    included do
      validate :validate_nif_registration_schema, if: -> { record_type == "nif_registration" && status != "draft" }
    end

    DEPARTEMENTS_HAITI = [
      "Ouest", "Sud-Est", "Nord", "Nord-Est", "Artibonite",
      "Centre", "Sud", "Grand'Anse", "Nord-Ouest", "Nippes"
    ].freeze

    TYPES_ACTIVITE = {
      "salarie"               => "Salarye",
      "independant"           => "Endepandan",
      "commercant"            => "Komesyan",
      "professionnel_liberal" => "Pwofesyonel Liberal",
      "agriculteur"           => "Agrikilte",
      "retraite"              => "Retrete",
      "sans_emploi"           => "San Travay",
      "etudiant"              => "Etidyan",
      "autre"                 => "Lot"
    }.freeze

    ETATS_CIVILS = {
      "celibataire" => "Selibate",
      "marie"       => "Marye",
      "divorce"     => "Divose",
      "veuf"        => "Vef/Vev",
      "union_libre" => "Inyon Lib"
    }.freeze

    SEXES = { "M" => "Gason", "F" => "Fi" }.freeze

    # ================================================================
    # Validation
    # ================================================================
    def validate_nif_registration_schema
      return unless data.is_a?(Hash)

      personne = data["personne"] || {}
      adresse  = data["adresse"] || {}

      # Personne
      missing = []
      missing << "nom"             unless personne["nom"].present?
      missing << "prenom"          unless personne["prenom"].present?
      missing << "date_naissance"  unless personne["date_naissance"].present?
      missing << "lieu_naissance"  unless personne["lieu_naissance"].present?
      errors.add(:data, "Chan obligatwa ki manke: #{missing.join(', ')} (Idantifikasyon)") if missing.any?

      if personne["sexe"].present? && !%w[M F].include?(personne["sexe"])
        errors.add(:data, "Seks dwe 'M' oswa 'F'")
      end

      if personne["etat_civil"].present? && !ETATS_CIVILS.key?(personne["etat_civil"])
        errors.add(:data, "Eta sivil pa valid")
      end

      if personne["date_naissance"].present?
        begin
          dob = Date.parse(personne["date_naissance"])
          errors.add(:data, "Dat nesans dwe nan pase") if dob > Date.current
          errors.add(:data, "Dat nesans pa reyalis") if dob < Date.new(1900, 1, 1)
        rescue ArgumentError
          errors.add(:data, "Dat nesans pa valid")
        end
      end

      # Adresse
      addr_missing = []
      addr_missing << "rue"         unless adresse["rue"].present?
      addr_missing << "commune"     unless adresse["commune"].present?
      addr_missing << "departement" unless adresse["departement"].present?
      addr_missing << "telephone"   unless adresse["telephone"].present?
      errors.add(:data, "Chan adrès obligatwa ki manke: #{addr_missing.join(', ')}") if addr_missing.any?

      if adresse["departement"].present? && !DEPARTEMENTS_HAITI.include?(adresse["departement"])
        errors.add(:data, "Depatman pa valid. Dwe youn nan: #{DEPARTEMENTS_HAITI.join(', ')}")
      end

      # Activite
      activite = data["activite"] || {}
      if activite["type_activite"].present? && !TYPES_ACTIVITE.key?(activite["type_activite"])
        errors.add(:data, "Tip aktivite pa valid")
      end
    end

    # ================================================================
    # NIF Generator
    # ================================================================
    def self.generate_nif
      digits = 9.times.map { rand(10) }.join
      "#{digits[0..2]}-#{digits[3..5]}-#{digits[6..8]}"
    end

    # ================================================================
    # Accessors
    # ================================================================

    # Reference
    def nif_reference_number = data["reference_number"]

    # Personne
    def nif_nom              = data.dig("personne", "nom")
    def nif_prenom           = data.dig("personne", "prenom")
    def nif_date_naissance   = data.dig("personne", "date_naissance")
    def nif_lieu_naissance   = data.dig("personne", "lieu_naissance")
    def nif_sexe             = data.dig("personne", "sexe")
    def nif_etat_civil       = data.dig("personne", "etat_civil")
    def nif_nationalite      = data.dig("personne", "nationalite")
    def nif_numero_cin       = data.dig("personne", "numero_cin")
    def nif_numero_passeport = data.dig("personne", "numero_passeport")

    def nif_nom_complet
      [ nif_prenom, nif_nom ].compact.join(" ")
    end

    def nif_sexe_label
      SEXES[nif_sexe] || "---"
    end

    def nif_etat_civil_label
      ETATS_CIVILS[nif_etat_civil] || "---"
    end

    # Adresse
    def nif_adresse_rue  = data.dig("adresse", "rue")
    def nif_ville        = data.dig("adresse", "ville")
    def nif_departement  = data.dig("adresse", "departement")
    def nif_commune      = data.dig("adresse", "commune")
    def nif_code_postal  = data.dig("adresse", "code_postal")
    def nif_telephone    = data.dig("adresse", "telephone")
    def nif_email        = data.dig("adresse", "email")

    # Activite
    def nif_type_activite       = data.dig("activite", "type_activite")
    def nif_description_activite = data.dig("activite", "description_activite")
    def nif_nom_employeur       = data.dig("activite", "nom_employeur")
    def nif_adresse_employeur   = data.dig("activite", "adresse_employeur")
    def nif_revenu_annuel       = data.dig("activite", "revenu_annuel_estime").to_f

    def nif_type_activite_label
      TYPES_ACTIVITE[nif_type_activite] || "---"
    end

    # NIF Generated
    def nif_genere       = data.dig("nif", "nif_genere")
    def nif_date_emission = data.dig("nif", "date_emission")
    def nif_bureau_dgi   = data.dig("nif", "bureau_dgi")

    # Display
    def nif_registration_summary
      "NIF #{nif_genere} - #{nif_nom_complet} - #{nif_ville}"
    end
  end
end
