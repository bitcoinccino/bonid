# frozen_string_literal: true

# BonID — Business Registration Schema (Formulaire B - Entreprise Individuelle)
# ===============================================================================
# Official DGI form for registering a sole proprietorship / individual business.
# Gateway form: every business needs this BEFORE getting a patente, filing TCA,
# or filing RAS IR. Links the owner's BonID + NIF to the business permanently.
#
# 5 Sections matching the real DGI Formulaire B exactly:
#   Section 1: Informations Generales (fields 1-15)
#   Section 2: Le Proprietaire (fields 16-21)
#   Section 3: Information de Contact (fields 22-28)
#   Section 4: Adresse + Etablissements (fields 29-30)
#   Section 5: Certification (signature + date)
# ===============================================================================

module RecordSchemas
  module BusinessRegistrationSchema
    extend ActiveSupport::Concern

    included do
      validate :validate_business_registration_schema, if: -> { record_type == "business_registration" && status != "draft" }
    end

    DEPARTEMENTS_HAITI = [
      "Ouest", "Sud-Est", "Nord", "Nord-Est", "Artibonite",
      "Centre", "Sud", "Grand'Anse", "Nord-Ouest", "Nippes"
    ].freeze

    # Same ISIC-based sector codes used across DGI forms
    SECTEUR_ACTIVITE_BIZ = {
      "A" => "Agrikilti, Elvaj, Lapes",
      "B" => "Endistri Ekstraksyon (Min, Karye)",
      "C" => "Endistri Manifakti",
      "D" => "Distribisyon Elektrisite, Gaz, Dlo",
      "E" => "Jesyon Dlo ak Deche",
      "F" => "Konstriksyon",
      "G" => "Komes (Angwo ak Detay)",
      "H" => "Transpo ak Antrepozaj",
      "I" => "Otel, Restoran, Touris",
      "J" => "Enfomasyon ak Kominikasyon",
      "K" => "Aktivite Finansye ak Asirans",
      "L" => "Aktivite Imobilye",
      "M" => "Aktivite Pwofesyonel, Syantifik, Teknik",
      "N" => "Sevis Administratif ak Sipo",
      "O" => "Administrasyon Piblik",
      "P" => "Edikasyon",
      "Q" => "Sante ak Aksyon Sosyal",
      "R" => "Atizay, Espektik, Lwazi",
      "S" => "Lot Aktivite Sevis",
      "T" => "Aktivite Domestik",
      "U" => "Oganizasyon Entenasyonal"
    }.freeze

    NATIONALITE_ENTREPRISE = {
      "haitienne" => "Ayisyen",
      "etrangere" => "Etranje"
    }.freeze

    # ================================================================
    # Validation
    # ================================================================
    def validate_business_registration_schema
      return unless data.is_a?(Hash)

      general     = data["informations_generales"] || {}
      proprietaire = data["proprietaire"] || {}
      contact     = data["contact"] || {}
      adresse     = data["adresse"] || {}

      # Section 1 — Informations Generales
      s1_missing = []
      s1_missing << "raison_sociale (3)"           unless general["raison_sociale"].present?
      s1_missing << "date_creation (5)"             unless general["date_creation"].present?
      s1_missing << "secteur_activite_primaire (14)" unless general["secteur_activite_primaire"].present?
      errors.add(:data, "Chan obligatwa ki manke: #{s1_missing.join(', ')} (Section 1)") if s1_missing.any?

      if general["nif"].present? && !general["nif"].match?(/\A(\d{3}-\d{3}-\d{3}|NIF-HT-\d{9})\z/)
        errors.add(:data, "NIF dwe nan foma XXX-XXX-XXX oswa NIF-HT-XXXXXXXXX")
      end

      if general["date_creation"].present?
        begin
          dc = Date.parse(general["date_creation"])
          errors.add(:data, "Dat kreyasyon dwe nan pase oswa jodi a") if dc > Date.current
        rescue ArgumentError
          errors.add(:data, "Dat kreyasyon pa valid")
        end
      end

      if general["date_debut_operations"].present?
        begin
          Date.parse(general["date_debut_operations"])
        rescue ArgumentError
          errors.add(:data, "Dat komansman operasyon pa valid")
        end
      end

      if general["nombre_employes"].present?
        errors.add(:data, "Kantite anplwaye dwe yon nimewo pozitif") unless general["nombre_employes"].to_i >= 0
      end

      if general["chiffre_affaires"].present?
        errors.add(:data, "Chif afe dwe yon nimewo valid") unless general["chiffre_affaires"].to_s.match?(/\A\d+(\.\d+)?\z/)
      end

      # Section 2 — Le Proprietaire
      s2_missing = []
      s2_missing << "prenom_proprietaire (17)" unless proprietaire["prenom"].present?
      s2_missing << "nom_proprietaire (18)"    unless proprietaire["nom"].present?
      errors.add(:data, "Chan obligatwa ki manke: #{s2_missing.join(', ')} (Section 2)") if s2_missing.any?

      if proprietaire["nif"].present? && !proprietaire["nif"].match?(/\A(\d{3}-\d{3}-\d{3}|NIF-HT-\d{9})\z/)
        errors.add(:data, "NIF pwopriyete dwe nan foma XXX-XXX-XXX oswa NIF-HT-XXXXXXXXX")
      end

      if proprietaire["nif_directeur"].present? && !proprietaire["nif_directeur"].match?(/\A(\d{3}-\d{3}-\d{3}|NIF-HT-\d{9})\z/)
        errors.add(:data, "NIF direkte dwe nan foma XXX-XXX-XXX oswa NIF-HT-XXXXXXXXX")
      end

      # Section 3 — Contact
      errors.add(:data, "Telefon mobil obligatwa (22, Section 3)") unless contact["telephone_mobile"].present?
      errors.add(:data, "Adrès imel prensipal obligatwa (25, Section 3)") unless contact["email_primaire"].present?

      # Section 4 — Adresse
      s4_missing = []
      s4_missing << "departement (29a)" unless adresse["departement"].present?
      s4_missing << "commune (29b)"     unless adresse["commune"].present?
      s4_missing << "adresse (29e)"     unless adresse["adresse"].present?
      errors.add(:data, "Chan adrès obligatwa ki manke: #{s4_missing.join(', ')} (Section 4)") if s4_missing.any?

      if adresse["departement"].present? && !DEPARTEMENTS_HAITI.include?(adresse["departement"])
        errors.add(:data, "Depatman pa valid")
      end

      # Section 4 — Etablissements (optional, up to 5)
      etablissements = data["etablissements"]
      if etablissements.is_a?(Array)
        etablissements.each_with_index do |etab, idx|
          if etab["adresse"].blank? && etab["nom_commercial"].blank?
            next # skip empty entries
          end
          errors.add(:data, "Etablisman #{idx + 1}: adrès obligatwa") if etab["adresse"].blank?
          errors.add(:data, "Etablisman #{idx + 1}: depatman obligatwa") if etab["departement"].blank?
        end
      end
    end

    # ================================================================
    # Registration Number Generator
    # ================================================================
    def self.generate_registration_number(office: "PAP")
      seq = rand(1_000_000..9_999_999)
      "ENT-#{Time.current.year}-#{office}-#{seq}"
    end

    # ================================================================
    # Accessors
    # ================================================================

    # Reference
    def biz_reference_number       = data["reference_number"]
    def biz_registration_number    = data.dig("informations_generales", "numero_enregistrement")

    # Section 1 — Informations Generales
    def biz_nif                    = data.dig("informations_generales", "nif")
    def biz_raison_sociale         = data.dig("informations_generales", "raison_sociale")
    def biz_nom_commercial         = data.dig("informations_generales", "nom_commercial")
    def biz_date_creation          = data.dig("informations_generales", "date_creation")
    def biz_date_debut_operations  = data.dig("informations_generales", "date_debut_operations")
    def biz_periode_financiere     = data.dig("informations_generales", "periode_financiere")
    def biz_nombre_employes        = data.dig("informations_generales", "nombre_employes").to_i
    def biz_a_patente              = data.dig("informations_generales", "a_patente")
    def biz_numero_patente         = data.dig("informations_generales", "numero_patente")
    def biz_exempte_tms            = data.dig("informations_generales", "exempte_taxe_masse_salariale")
    def biz_nationalite            = data.dig("informations_generales", "nationalite_entreprise")
    def biz_sexe_proprietaire      = data.dig("informations_generales", "sexe_proprietaire")
    def biz_chiffre_affaires       = data.dig("informations_generales", "chiffre_affaires").to_f
    def biz_verificateur_externe   = data.dig("informations_generales", "verificateur_externe")
    def biz_secteur_primaire       = data.dig("informations_generales", "secteur_activite_primaire")
    def biz_secteurs_secondaires   = data.dig("informations_generales", "secteurs_activite_secondaires")

    def biz_secteur_primaire_label
      SECTEUR_ACTIVITE_BIZ[biz_secteur_primaire&.upcase] || biz_secteur_primaire || "---"
    end

    # Section 2 — Le Proprietaire
    def biz_proprietaire_nif       = data.dig("proprietaire", "nif")
    def biz_proprietaire_prenom    = data.dig("proprietaire", "prenom")
    def biz_proprietaire_nom       = data.dig("proprietaire", "nom")
    def biz_directeur_nif          = data.dig("proprietaire", "nif_directeur")
    def biz_directeur_prenom       = data.dig("proprietaire", "prenom_directeur")
    def biz_directeur_nom          = data.dig("proprietaire", "nom_directeur")

    def biz_proprietaire_nom_complet
      [ biz_proprietaire_prenom, biz_proprietaire_nom ].compact.join(" ")
    end

    def biz_directeur_nom_complet
      nom = [ data.dig("proprietaire", "prenom_directeur"), data.dig("proprietaire", "nom_directeur") ].compact.join(" ")
      nom.present? ? nom : nil
    end

    # Section 3 — Information de Contact
    def biz_telephone_mobile       = data.dig("contact", "telephone_mobile")
    def biz_telephone_fixe         = data.dig("contact", "telephone_fixe")
    def biz_fax                    = data.dig("contact", "fax")
    def biz_email_primaire         = data.dig("contact", "email_primaire")
    def biz_email_secondaire       = data.dig("contact", "email_secondaire")
    def biz_comptable_nif          = data.dig("contact", "nif_comptable")
    def biz_comptable_nom          = data.dig("contact", "nom_comptable")

    # Section 4 — Adresse (field 29)
    def biz_departement            = data.dig("adresse", "departement")
    def biz_commune                = data.dig("adresse", "commune")
    def biz_section_communale      = data.dig("adresse", "section_communale")
    def biz_zone                   = data.dig("adresse", "zone")
    def biz_adresse                = data.dig("adresse", "adresse")
    def biz_pays                   = data.dig("adresse", "pays")
    def biz_info_localisation      = data.dig("adresse", "info_additionnelle")

    # Section 4 — Etablissements (field 30, array of up to 5)
    def biz_etablissements         = data["etablissements"] || []
    def biz_a_autres_etablissements = biz_etablissements.any?

    # Section 5 — Certification
    def biz_certifie_par           = data.dig("certification", "nom")
    def biz_date_certification     = data.dig("certification", "date")

    # Display
    def business_registration_summary
      "#{biz_raison_sociale} (#{biz_secteur_primaire_label}) - #{biz_proprietaire_nom_complet}"
    end

    # ================================================================
    # Form Fields — matching DGI Formulaire B exactly
    # ================================================================
    FORM_FIELDS = {
      # Section 1 — Informations Generales
      1  => { key: "nif",                          section: 1, label: "NIF (nimewo idantifikasyon fiskal)",                  required: false },
      2  => { key: "numero_enregistrement",         section: 1, label: "Nimewo anrejistreman",                               required: false },
      3  => { key: "raison_sociale",                section: 1, label: "Rezon sosyal",                                       required: true },
      4  => { key: "nom_commercial",                section: 1, label: "Non komesyal (si genyen)",                            required: false },
      5  => { key: "date_creation",                 section: 1, label: "Dat kreyasyon",                                      required: true },
      6  => { key: "date_debut_operations",         section: 1, label: "Dat komansman operasyon",                             required: false },
      7  => { key: "periode_financiere",            section: 1, label: "Peryod finansyè",                                    required: false },
      8  => { key: "nombre_employes",               section: 1, label: "Kantite anplwaye",                                   required: false },
      9  => { key: "a_patente",                     section: 1, label: "Ou gen oswa ou ap gen yon patant? Si wi, nimewo.",    required: false, type: :boolean },
      10 => { key: "exempte_taxe_masse_salariale",  section: 1, label: "Ou egzante de taks sou mas salaryal?",               required: false },
      11 => { key: "nationalite_entreprise",        section: 1, label: "Nasyonalite antrepriz (Gason/Fi)",                    required: false },
      12 => { key: "chiffre_affaires",              section: 1, label: "Chif afe dènye eta finansye",                         required: false },
      13 => { key: "verificateur_externe",          section: 1, label: "Eta finansye dwe verifye pa yon verifika'tè estèn? (chif afe > 25M)", required: false, type: :boolean },
      14 => { key: "secteur_activite_primaire",     section: 1, label: "Sektè aktivite primè",                               required: true },
      15 => { key: "secteurs_activite_secondaires", section: 1, label: "Sektè aktivite segondè",                             required: false },
      # Section 2 — Le Proprietaire
      16 => { key: "nif_proprietaire",              section: 2, label: "NIF pwopriyetè",                                     required: false, auto_fill: "nif" },
      17 => { key: "prenom_proprietaire",           section: 2, label: "Prenon pwopriyetè",                                  required: true,  auto_fill: "first_name" },
      18 => { key: "nom_proprietaire",              section: 2, label: "Non pwopriyetè",                                     required: true,  auto_fill: "last_name" },
      19 => { key: "nif_directeur",                 section: 2, label: "NIF direkte",                                        required: false },
      20 => { key: "prenom_directeur",              section: 2, label: "Prenon direkte",                                     required: false },
      21 => { key: "nom_directeur",                 section: 2, label: "Non direkte",                                        required: false },
      # Section 3 — Information de Contact
      22 => { key: "telephone_mobile",              section: 3, label: "Nimewo telefon mobil",                                required: true,  auto_fill: "phone" },
      23 => { key: "telephone_fixe",                section: 3, label: "Nimewo telefon fiks",                                 required: false },
      24 => { key: "fax",                           section: 3, label: "Nimewo faks",                                        required: false },
      25 => { key: "email_primaire",                section: 3, label: "Adrès imel prensipal",                                required: true,  auto_fill: "email" },
      26 => { key: "email_secondaire",              section: 3, label: "Adrès imel segondè",                                 required: false },
      27 => { key: "nif_comptable",                 section: 3, label: "NIF kontab estèn",                                   required: false },
      28 => { key: "nom_comptable",                 section: 3, label: "Non kontab estèn",                                   required: false },
      # Section 4 — Adresse
      "29a" => { key: "departement",                section: 4, label: "Depatman",                                           required: true,  auto_fill: "birth_department" },
      "29b" => { key: "commune",                    section: 4, label: "Komin",                                              required: true,  auto_fill: "birth_commune" },
      "29c" => { key: "section_communale",          section: 4, label: "Seksyon kominal",                                    required: false },
      "29d" => { key: "zone",                       section: 4, label: "Zòn",                                                required: false },
      "29e" => { key: "adresse",                    section: 4, label: "Adrès",                                              required: true,  auto_fill: "street_address" },
      "29f" => { key: "pays",                       section: 4, label: "Peyi Rezidans",                                      required: false, auto_fill: "country" },
      "29g" => { key: "info_additionnelle",         section: 4, label: "Enfòmasyon adisyonèl lokalizasyon",                   required: false }
    }.freeze

    SECTION_LABELS = {
      1 => "Enfòmasyon Jeneral",
      2 => "Pwopriyetè a",
      3 => "Enfòmasyon Kontak",
      4 => "Adrès ak Etablisman",
      5 => "Sètifikasyon"
    }.freeze

    # Fields auto-populated from BonID citizen record
    BONID_AUTO_FIELDS = %w[
      proprietaire.prenom
      proprietaire.nom
      contact.telephone_mobile
      contact.email_primaire
      adresse.departement
      adresse.commune
      adresse.adresse
      adresse.pays
    ].freeze

    # Required supporting documents
    PIECES_JUSTIFICATIVES = [
      "Sètifika anrejistreman Ministè Komès",
      "Yon kopi prèv adrès (kont elektrisite, kont dlo, resi transfè, resi DHL)"
    ].freeze
  end
end
