# frozen_string_literal: true

# BonID — RAS IR Declaration Schema (DGI-F005 — Retenues à la Source Mensuelles)
# ================================================================================
# Official DGI form No. 005-1 for monthly withholding tax.
# Employers report 3 income categories (salaries, bonuses, dividends),
# calculate withholding taxes, plus FDU (1%), CAS (1%), DSAV (2/1000).
#
# Section IV has 14 lines matching the real DGI-F005 form exactly.
# Section VI has admin fields (montant à payer, intérêts, amende, total).
# ================================================================================

module RecordSchemas
  module RasIrDeclarationSchema
    extend ActiveSupport::Concern

    included do
      validate :validate_ras_ir_declaration_schema, if: -> { record_type == "ras_ir_declaration" && status != "draft" }
    end

    # Haiti Income Tax Brackets (annual amounts in HTG)
    TRANCHES_IR = [
      { min: 0,       max: 120_000,  rate: 0.00, label: "0 - 120,000 HTG: 0%" },
      { min: 120_001, max: 240_000,  rate: 0.10, label: "120,001 - 240,000 HTG: 10%" },
      { min: 240_001, max: 480_000,  rate: 0.15, label: "240,001 - 480,000 HTG: 15%" },
      { min: 480_001, max: 800_000,  rate: 0.25, label: "480,001 - 800,000 HTG: 25%" },
      { min: 800_001, max: Float::INFINITY, rate: 0.30, label: "800,001+ HTG: 30%" }
    ].freeze

    # Rates from DGI-F005
    TAUX_BONIS          = 10.0 / 100   # 10% flat on bonuses
    TAUX_DIVIDENDES     = 20.0 / 100   # 20% flat on dividends
    TAUX_FDU            = 1.0 / 100    # 1% Fond d'Urgence
    TAUX_CAS            = 1.0 / 100    # 1% Caisse Assistance Sociale
    TAUX_DSAV_RAS       = 2.0 / 1000   # 2/1000 DSAV

    # Sector codes (same as Patente — DGI uses the same ISIC-based codes)
    SECTEUR_ACTIVITE_RAS = {
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

    # ================================================================
    # Validation
    # ================================================================
    def validate_ras_ir_declaration_schema
      return unless data.is_a?(Hash)

      periode = data["periode"] || {}
      ident   = data["identification"] || {}
      calcul  = data["calcul_ras"] || {}

      # Section I — Periode d'imposition
      errors.add(:data, "Ane fiskal obligatwa (Section I)") if periode["annee_fiscale"].blank?
      if periode["annee_fiscale"].present? && !periode["annee_fiscale"].match?(/\A\d{4}-\d{4}\z/)
        errors.add(:data, "Ane fiskal dwe nan foma YYYY-YYYY")
      end
      errors.add(:data, "Mwa deklarasyon obligatwa (Section I)") if periode["mois_declaration"].blank?
      if periode["mois_declaration"].present? && !(1..12).include?(periode["mois_declaration"].to_i)
        errors.add(:data, "Mwa deklarasyon dwe ant 1 ak 12")
      end

      # Section II — Type de declaration
      if periode["type_declaration"].present?
        unless %w[originale rectificative].include?(periode["type_declaration"])
          errors.add(:data, "Tip deklarasyon dwe 'originale' oswa 'rectificative'")
        end
      else
        errors.add(:data, "Tip deklarasyon obligatwa (Section II)")
      end

      # Section III — Identification
      missing = []
      missing << "raison_sociale" unless ident["raison_sociale"].present?
      missing << "nif"            unless ident["nif"].present?
      missing << "adresse"        unless ident["adresse"].present?
      missing << "ville"          unless ident["ville"].present?
      errors.add(:data, "Chan obligatwa ki manke: #{missing.join(', ')} (Section III)") if missing.any?

      if ident["nif"].present? && !ident["nif"].match?(/\A(\d{3}-\d{3}-\d{3}|NIF-HT-\d{9})\z/)
        errors.add(:data, "NIF dwe nan foma XXX-XXX-XXX oswa NIF-HT-XXXXXXXXX")
      end

      if ident["code_secteur"].present? && !SECTEUR_ACTIVITE_RAS.key?(ident["code_secteur"].upcase)
        errors.add(:data, "Kod sekte aktivite pa valid")
      end

      # Section IV — Calcul (Line 1 required minimum)
      errors.add(:data, "Salè total mansyel obligatwa (Liy 1, Section IV)") if calcul["salaires_montant"].blank?

      # Numeric validation for all calculation fields
      numeric_fields = %w[
        salaires_montant salaires_impot
        bonis_montant bonis_impot
        dividendes_montant dividendes_impot
        montant_impot_a_payer fdu cas dsav
      ]
      numeric_fields.each do |field|
        val = calcul[field]
        next if val.blank?
        errors.add(:data, "#{field} dwe yon nimewo valid") unless val.to_s.match?(/\A-?\d+(\.\d+)?\z/)
      end

      # Employee list validation
      employes = data["employes"]
      if employes.is_a?(Array)
        employes.each_with_index do |emp, idx|
          errors.add(:data, "Anplwaye #{idx + 1}: non obligatwa") if emp["nom_employe"].blank?
          errors.add(:data, "Anplwaye #{idx + 1}: salè brit obligatwa") if emp["salaire_brut"].blank?
        end
      end
    end

    # ================================================================
    # IR Calculation for a single annual salary (progressive brackets)
    # ================================================================
    def self.calculate_ir_for_salary(annual_salary)
      salary = annual_salary.to_f
      tax = 0.0

      TRANCHES_IR.each do |tranche|
        break if salary <= 0

        taxable_in_bracket = [ salary, tranche[:max] ].min - [ tranche[:min] - 1, 0 ].max
        taxable_in_bracket = [ taxable_in_bracket, 0 ].max
        tax += taxable_in_bracket * tranche[:rate]
        salary -= taxable_in_bracket
      end

      tax.round(2)
    end

    # ================================================================
    # RAS Calculation Engine (matches DGI-F005 Section IV exactly)
    # ================================================================
    # Inputs from form:
    #   - salaires_montant:    Line 1 — total monthly salaries
    #   - salaires_impot:      Line 2 — IR withheld on salaries (from employee list or manual)
    #   - bonis_montant:       Line 3 — bonuses/overtime gross
    #   - bonis_impot:         Line 4 — 10% flat tax on bonuses (auto-calc or manual)
    #   - dividendes_montant:  Line 5 — dividends/distributions gross
    #   - dividendes_impot:    Line 6 — 20% flat tax on dividends (auto-calc or manual)
    #   - employes:            Line 11 — employee list (annexe)
    #   - interets_retard:     Section VI
    #   - amende:              Section VI
    def calculate_ras(
      salaires_montant: 0, salaires_impot: nil,
      bonis_montant: 0, bonis_impot: nil,
      dividendes_montant: 0, dividendes_impot: nil,
      employes: [],
      interets_retard: 0, amende: 0
    )
      # Line 1 — Salaires montant total mensuel
      sal_montant = salaires_montant.to_f

      # Line 2 — Salaires impôt (from employee list if provided, else manual)
      emp_list = Array(employes)
      if salaires_impot.present?
        sal_impot = salaires_impot.to_f
      elsif emp_list.any?
        sal_impot = emp_list.sum { |e| e["retenue_ir"].to_f }
      else
        sal_impot = 0.0
      end

      # Line 3 — Bonis, étrennes et heures supplémentaires — montant
      bon_montant = bonis_montant.to_f

      # Line 4 — Bonis impôt (10% flat)
      bon_impot = bonis_impot.present? ? bonis_impot.to_f : (bon_montant * TAUX_BONIS).round(2)

      # Line 5 — Revenus distribués ou dividendes — montant
      div_montant = dividendes_montant.to_f

      # Line 6 — Dividendes impôt (20% flat)
      div_impot = dividendes_impot.present? ? dividendes_impot.to_f : (div_montant * TAUX_DIVIDENDES).round(2)

      # Line 7 — Montant de l'impôt à payer (sum of Lines 2 + 4 + 6)
      montant_impot = (sal_impot + bon_impot + div_impot).round(2)

      # Line 8 — FDU (Line 1 × 1%)
      fdu = (sal_montant * TAUX_FDU).round(2)

      # Line 9 — CAS (Line 1 × 1%)
      cas = (sal_montant * TAUX_CAS).round(2)

      # Line 10 — DSAV (2/1000 of montant_impot)
      dsav = (montant_impot * TAUX_DSAV_RAS).round(2)

      # Section VI — Administration
      ir  = interets_retard.to_f
      am  = amende.to_f
      montant_a_payer = (montant_impot + fdu + cas + dsav).round(2)
      total = (montant_a_payer + ir + am).round(2)

      {
        # Section IV — Lines 1-10
        "salaires_montant"     => sal_montant.round(2),
        "salaires_impot"       => sal_impot.round(2),
        "bonis_montant"        => bon_montant.round(2),
        "bonis_impot"          => bon_impot,
        "dividendes_montant"   => div_montant.round(2),
        "dividendes_impot"     => div_impot,
        "montant_impot_a_payer" => montant_impot,
        "fdu"                  => fdu,
        "cas"                  => cas,
        "dsav"                 => dsav,
        # Section VI — Admin
        "nombre_employes"      => emp_list.size,
        "montant_a_payer"      => montant_a_payer,
        "interets_retard"      => ir.round(2),
        "amende"               => am.round(2),
        "total"                => total
      }
    end

    # ================================================================
    # Accessors
    # ================================================================

    # Declaration Number
    def ras_declaration_number = data["declaration_number"]

    # Periode (Section I)
    def ras_annee_fiscale     = data.dig("periode", "annee_fiscale")
    def ras_mois_declaration  = data.dig("periode", "mois_declaration")&.to_i
    def ras_type_declaration  = data.dig("periode", "type_declaration")

    # Identification (Section III)
    def ras_raison_sociale    = data.dig("identification", "raison_sociale")
    def ras_nif               = data.dig("identification", "nif")
    def ras_adresse           = data.dig("identification", "adresse")
    def ras_ville             = data.dig("identification", "ville")
    def ras_telephone         = data.dig("identification", "telephone")
    def ras_email             = data.dig("identification", "email")
    def ras_code_secteur      = data.dig("identification", "code_secteur")
    def ras_nom_secteur       = data.dig("identification", "nom_secteur")

    def ras_secteur_label
      SECTEUR_ACTIVITE_RAS[ras_code_secteur&.upcase] || ras_nom_secteur || "---"
    end

    # Calcul — Section IV (Lines 1-10)
    def ras_salaires_montant     = data.dig("calcul_ras", "salaires_montant").to_f
    def ras_salaires_impot       = data.dig("calcul_ras", "salaires_impot").to_f
    def ras_bonis_montant        = data.dig("calcul_ras", "bonis_montant").to_f
    def ras_bonis_impot          = data.dig("calcul_ras", "bonis_impot").to_f
    def ras_dividendes_montant   = data.dig("calcul_ras", "dividendes_montant").to_f
    def ras_dividendes_impot     = data.dig("calcul_ras", "dividendes_impot").to_f
    def ras_montant_impot        = data.dig("calcul_ras", "montant_impot_a_payer").to_f
    def ras_fdu                  = data.dig("calcul_ras", "fdu").to_f
    def ras_cas                  = data.dig("calcul_ras", "cas").to_f
    def ras_dsav                 = data.dig("calcul_ras", "dsav").to_f

    # Calcul — Section VI (Admin)
    def ras_nombre_employes      = data.dig("calcul_ras", "nombre_employes").to_i
    def ras_montant_a_payer      = data.dig("calcul_ras", "montant_a_payer").to_f
    def ras_interets_retard      = data.dig("calcul_ras", "interets_retard").to_f
    def ras_amende               = data.dig("calcul_ras", "amende").to_f
    def ras_total                = data.dig("calcul_ras", "total").to_f

    # Employes (Line 11 — Annexe)
    def ras_employes             = data["employes"] || []

    # Paiement (Section VI)
    def ras_methode_paiement     = data.dig("paiement", "methode")
    def ras_numero_cheque        = data.dig("paiement", "numero_cheque")
    def ras_banque               = data.dig("paiement", "banque")

    # Signature (Section V)
    def ras_declarant_nom        = data.dig("signature", "nom_prenom")
    def ras_declarant_nif        = data.dig("signature", "nif_declarant")
    def ras_date_presentation    = data.dig("signature", "date_presentation")

    # Display
    def ras_summary
      "RAS IR #{ras_annee_fiscale}/#{ras_mois_declaration} - #{ras_raison_sociale} - #{ras_total.round(2)} HTG (#{ras_nombre_employes} anplwaye)"
    end

    # ================================================================
    # Section IV — Lines matching DGI-F005 exactly
    # ================================================================
    CALCUL_RAS_LINES = {
      1  => { key: "salaires_montant",      label: "Salè - montan total mansyel",                                  editable: true },
      2  => { key: "salaires_impot",        label: "Salè - enpo total pou peye",                                   editable: true },
      3  => { key: "bonis_montant",         label: "Boni, etrèn ak Lè siplemantè - montan total mansyel",          editable: true },
      4  => { key: "bonis_impot",           label: "Boni, etrèn ak Lè siplemantè - enpo total pou peye",           editable: true, rate: "10%" },
      5  => { key: "dividendes_montant",    label: "Revni distribye oswa dividand - montan total mansyel",          editable: true },
      6  => { key: "dividendes_impot",      label: "Revni distribye oswa dividand - enpo total pou peye",           editable: true, rate: "20%" },
      7  => { key: "montant_impot_a_payer", label: "Montan enpo pou peye",                                         editable: false },
      8  => { key: "fdu",                   label: "FDU - Fon Dijans (Liy 1 × 1%)",                                editable: false, rate: "1%" },
      9  => { key: "cas",                   label: "CAS - Kès Asistans Sosyal (Liy 1 × 1%)",                       editable: false, rate: "1%" },
      10 => { key: "dsav",                  label: "DSAV",                                                          editable: false, rate: "2/1000" },
      11 => { key: "employes",              label: "Lis anplwaye (ak/oswa benefisyè) - Ranpli anèks (nan do)",      editable: false },
      12 => { key: "nouvelle_adresse",      label: "Nouvo adrès",                                                   editable: true, admin: true },
      13 => { key: "nouveau_telephone",     label: "Nouvo nimewo telefòn",                                          editable: true, admin: true },
      14 => { key: "nouvelle_email",        label: "Nouvo adrès imel / mesajri",                                    editable: true, admin: true }
    }.freeze

    # Section VI — Cadre réservé à l'administration
    ADMIN_LINES = {
      montant_a_payer:  "Montan pou Peye",
      interets_retard:  "Entere Reta",
      amende:           "Amand",
      total:            "TOTAL"
    }.freeze
  end
end
