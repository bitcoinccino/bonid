# frozen_string_literal: true

# Citizens::DgiController — Citizen Self-Service DGI Filing
# ==========================================================
# Citizens file DGI forms directly from their BonID dashboard.
# No BonID lookup needed — current_citizen IS the taxpayer.
# Records start as "pending" until a DGI partner reviews & approves.
#
# Supported form types (Tier 1):
#   - nif_registration       (Formulaire A)
#   - business_registration  (Formulaire B)
#   - patente_declaration    (DGI-F008)
#   - tca_declaration
#   - ras_ir_declaration     (DGI-F005)
# ==========================================================

module Citizens
  class DgiController < Citizens::BaseController
    before_action :set_citizen
    before_action :find_record, only: [:show, :resubmit, :update_resubmit]
    before_action :enable_immersive_form, only: [:new, :create, :show, :resubmit]

    FORM_TYPES = %w[
      nif_registration
      business_registration
      patente_declaration
      tca_declaration
      ras_ir_declaration
      fermage
    ].freeze

    FORM_LABELS = {
      "nif_registration"      => { title: "NIF Individi",      subtitle: "Formulaire A — Enskripsyon NIF", icon: "ri-id-card-line" },
      "business_registration" => { title: "Anrej. Biznis",      subtitle: "Formulaire B — Anrejistreman Biznis", icon: "ri-building-2-line" },
      "patente_declaration"   => { title: "Patant",             subtitle: "DGI-F008 — Taks Lisans Biznis", icon: "ri-store-2-line" },
      "tca_declaration"       => { title: "TCA",                subtitle: "Taks sou Chif Afe — 10%", icon: "ri-percent-line" },
      "ras_ir_declaration"    => { title: "RAS IR",             subtitle: "DGI-F005 — Retni nan Sous", icon: "ri-money-dollar-box-line" },
      "fermage"               => { title: "Fèmaj",             subtitle: "DGI-55 — Taks sou Lwaye Tè", icon: "ri-landscape-line" }
    }.freeze

    # ============================================================
    # INDEX — List all citizen's DGI filings
    # ============================================================
    def index
      @records = @citizen.verification_records
                   .where(record_type: FORM_TYPES)
                   .where.not(status: "draft")
                   .order(created_at: :desc)

      @records = @records.where(record_type: params[:form_type]) if params[:form_type].present? && FORM_TYPES.include?(params[:form_type])
      @records = @records.where(status: params[:status]) if params[:status].present?
      @records = @records.page(params[:page]).per(15)

      @payments = DgiPayment.for_user(@citizen).recent.limit(5)

      submitted = @citizen.verification_records.where(record_type: FORM_TYPES).where.not(status: "draft")
      @stats = {
        total: submitted.count,
        pending: submitted.where(status: "pending").count,
        verified: submitted.where(status: "verified").count,
        rejected: submitted.where(status: "rejected").count
      }
    end

    # ============================================================
    # SHOW — View a specific filing + payment status
    # ============================================================
    def show
      @payment = DgiPayment.find_by(verification_record: @record)
      @form_label = FORM_LABELS[@record.record_type]
    end

    # ============================================================
    # RESUBMIT — Show the rejected form for correction
    # ============================================================
    def resubmit
      unless @record.status == "rejected"
        return redirect_to citizens_dgi_path(@record), alert: "Sèlman fòm rejte ka re-soumèt."
      end

      @form_type  = @record.record_type
      @form_label = FORM_LABELS[@form_type]
      @auto_fill  = build_auto_fill
      @bonid_submission = @citizen.identity_submissions&.find_by(status: "approved")
      @draft_data = @record.data
      @draft_step = 0
      @resubmission = true

      # Form-specific data
      case @form_type
      when "ras_ir_declaration"
        @tranches = RecordSchemas::RasIrDeclarationSchema::TRANCHES_IR
        @secteurs = RecordSchemas::RasIrDeclarationSchema::SECTEUR_ACTIVITE_RAS
      when "patente_declaration"
        @secteurs = RecordSchemas::PatenteDeclarationSchema::SECTEUR_ACTIVITE rescue nil
      end

      render :new
    end

    # ============================================================
    # UPDATE_RESUBMIT — Process the corrected resubmission
    # ============================================================
    def update_resubmit
      unless @record.status == "rejected"
        return redirect_to citizens_dgi_path(@record), alert: "Sèlman fòm rejte ka re-soumèt."
      end

      @form_type = @record.record_type

      # Archive the previous rejection in the audit trail
      previous_rejection = @record.data["rejection"]
      resubmissions = @record.data["resubmissions"] || []
      resubmissions << {
        "resubmitted_at"    => Time.current.iso8601,
        "previous_rejection" => previous_rejection
      }

      # Build corrected data using the same builder methods as create
      corrected_record = send("build_#{@form_type}")
      corrected_data = corrected_record.data

      # Preserve original declaration number and filing metadata
      corrected_data["declaration_number"] = @record.data["declaration_number"]
      corrected_data["reference_number"]   = @record.data["reference_number"] if @record.data["reference_number"]
      corrected_data["filed_by"]           = @record.data["filed_by"]

      # Add audit trail
      corrected_data["resubmissions"]  = resubmissions
      corrected_data["resubmitted_at"] = Time.current.iso8601

      @record.update!(
        status: "pending",
        data: corrected_data
      )

      # Attach supporting documents if provided
      if params[:supporting_documents].present?
        params[:supporting_documents].each do |doc|
          @record.supporting_documents.attach(doc) if doc.is_a?(ActionDispatch::Http::UploadedFile)
        end
      end

      # Store certification in record data
      if params[:certification_accepted] == "1"
        @record.data["certification"] = {
          "accepted"     => true,
          "certified_by" => build_auto_fill[:full_name],
          "certified_at" => Time.current.iso8601
        }
        @record.save!
      end

      # Notify DGI that a resubmission is available
      Bongouv::DgiMailer.filing_confirmation(@record).deliver_later

      redirect_to citizens_dgi_path(@record),
                  notice: "Deklarasyon #{@record.data['declaration_number']} re-soumèt avèk siksè. Ap tann revizyon DGI."
    end

    # ============================================================
    # NEW — Start a new DGI filing (auto-filled from profile)
    # ============================================================
    def new
      @form_type = params[:form_type]
      unless FORM_TYPES.include?(@form_type)
        return redirect_to citizens_dgi_index_path, alert: "Tip fòm pa valid."
      end

      @form_label = FORM_LABELS[@form_type]
      @auto_fill  = build_auto_fill
      @bonid_submission = @citizen.identity_submissions&.find_by(status: "approved")

      # Discard draft if requested
      if params[:discard_draft] == "true"
        @citizen.verification_records.where(record_type: @form_type, status: "draft").destroy_all
      end

      # Load existing draft if any
      @draft = @citizen.verification_records.find_by(record_type: @form_type, status: "draft")
      @draft_data = @draft&.data || {}
      @draft_step = @draft_data["draft_step"].to_i

      # Form-specific data
      case @form_type
      when "ras_ir_declaration"
        @tranches = RecordSchemas::RasIrDeclarationSchema::TRANCHES_IR
        @secteurs = RecordSchemas::RasIrDeclarationSchema::SECTEUR_ACTIVITE_RAS
      when "patente_declaration"
        @secteurs = RecordSchemas::PatenteDeclarationSchema::SECTEUR_ACTIVITE rescue nil
      end
    end

    # ============================================================
    # SAVE_DRAFT — Auto-save form progress (AJAX)
    # ============================================================
    def save_draft
      form_type = params[:form_type]
      unless FORM_TYPES.include?(form_type)
        return render json: { error: "invalid" }, status: :unprocessable_entity
      end

      draft = @citizen.verification_records.find_by(record_type: form_type, status: "draft")

      form_data = params[:draft_data]&.permit!&.to_h || {}
      current_step = params[:current_step].to_i

      if draft
        draft.update!(
          data: draft.data.merge(form_data).merge("draft_step" => current_step, "draft_updated_at" => Time.current.iso8601)
        )
      else
        draft = @citizen.verification_records.create!(
          record_type: form_type,
          status: "draft",
          data: form_data.merge("filed_by" => "citizen", "draft_step" => current_step, "draft_updated_at" => Time.current.iso8601)
        )
      end

      render json: { id: draft.id, saved_at: Time.current.iso8601 }
    end

    # ============================================================
    # CREATE — Submit a new DGI filing
    # ============================================================
    def create
      @form_type = params[:form_type]
      unless FORM_TYPES.include?(@form_type)
        return redirect_to citizens_dgi_index_path, alert: "Tip fòm pa valid."
      end

      # Delete existing draft — the final submission replaces it
      @citizen.verification_records.where(record_type: @form_type, status: "draft").destroy_all

      # Build the record using the appropriate builder
      record = send("build_#{@form_type}")

      if record.save
        # Attach supporting documents if provided
        if params[:supporting_documents].present?
          params[:supporting_documents].each do |doc|
            record.supporting_documents.attach(doc) if doc.is_a?(ActionDispatch::Http::UploadedFile)
          end
        end

        # Store certification in record data
        if params[:certification_accepted] == "1"
          record.data["certification"] = {
            "accepted"   => true,
            "certified_by" => build_auto_fill[:full_name],
            "certified_at" => Time.current.iso8601
          }
          record.save!
        end

        # Send filing confirmation email
        Bongouv::DgiMailer.filing_confirmation(record).deliver_later

        # Determine if payment is needed
        if needs_payment?(record)
          payment = create_payment_for(record, params[:payment_method])
          redirect_to citizens_dgi_payment_path(payment),
                      notice: "Deklarasyon kreye. Tanpri peye pou kontinye."
        else
          redirect_to citizens_dgi_path(record),
                      notice: "Deklarasyon #{record.data['declaration_number']} soumèt avèk siksè. Ap tann revizyon DGI."
        end
      else
        flash[:alert] = record.errors.full_messages.join(", ")
        redirect_to new_citizens_dgi_path(form_type: @form_type)
      end
    end

    private

    def set_citizen
      @citizen = current_citizen
    end

    def enable_immersive_form
      @immersive_form = true
    end

    def find_record
      @record = @citizen.verification_records.where(record_type: FORM_TYPES).find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to citizens_dgi_index_path, alert: "Deklarasyon pa jwenn."
    end

    # ============================================================
    # Auto-fill data from citizen's BonID profile
    # ============================================================
    def build_auto_fill
      addr = @citizen.address # Full BonID Address association
      {
        first_name:        @citizen.first_name,
        last_name:         @citizen.last_name,
        full_name:         "#{@citizen.last_name} #{@citizen.first_name}".strip,
        phone:             @citizen.phone,
        email:             @citizen.email,
        # BonID full address hierarchy
        street_address:    addr&.street_address || @citizen.street_address,
        locality:          addr&.locality || @citizen.locality,
        department:        addr&.department&.name || @citizen.birth_department&.name,
        commune:           addr&.commune&.name || @citizen.birth_commune&.name,
        section_communale: addr&.communal_section&.name,
        arrondissement:    addr&.arrondissement&.name,
        zone:              nil, # Not stored on address model
        postal_code:       addr&.postal_code || @citizen.postal_code,
        country:           addr&.country || "Haiti",
        # Legacy aliases
        birth_department:  addr&.department&.name || @citizen.birth_department&.name,
        birth_commune:     addr&.commune&.name || @citizen.birth_commune&.name,
        # Personal info
        date_of_birth:     @citizen.dob,
        sex:               { "male" => "M", "female" => "F" }[@citizen.sex] || @citizen.sex,
        marital_status:    { "single" => "celibataire", "married" => "marie", "divorced" => "divorce", "widowed" => "veuf" }[@citizen.marital_status],
        nationality:       @citizen.nationality || "Ayisyen",
        cin:               @citizen.id_number,
        nif:               existing_nif
      }
    end

    # Look up citizen's existing NIF from previous registrations
    def existing_nif
      nif_record = @citizen.verification_records
                     .where(record_type: "nif_registration", status: "verified")
                     .order(created_at: :desc).first
      nif_record&.nif_genere
    end

    # ============================================================
    # Payment Logic
    # ============================================================
    def needs_payment?(record)
      # All forms need at least the service fee
      true
    end

    def create_payment_for(record, selected_method = nil)
      tax_amount = extract_tax_amount(record)
      dgi_fee    = dgi_base_fee(record.record_type)
      service_fee = DgiPayment.bongouv_fee_for(record.record_type)

      # amount_htg = DGI official fee + calculated tax
      # fee_htg    = BonID service fee only
      amount = tax_amount + dgi_fee
      method = resolve_payment_method(selected_method)

      DgiPayment.create!(
        user: @citizen,
        verification_record: record,
        form_type: record.record_type,
        declaration_number: record.data["declaration_number"],
        payment_method: method,
        amount_htg: amount,
        fee_htg: service_fee,
        total_htg: amount + service_fee,
        status: "pending"
      )
    end

    def dgi_base_fee(form_type)
      info = DgiPayment::DGI_FEES[form_type.to_s]
      return 0.0 unless info.is_a?(Hash)

      # Registration forms have explicit base/card/cip fees
      (info[:base] || 0.0) + (info[:card] || 0.0) + (info[:cip] || 0.0)
    end

    # Map select value → DgiPayment.PAYMENT_METHODS value
    # wallet_<id> → look up BankProfile to get provider (moncash/natcash)
    # bank_<id>   → bank_transfer
    # cash_window / bank_transfer → pass through
    def resolve_payment_method(selected)
      return "moncash" if selected.blank?
      return selected if %w[moncash natcash zellus bank_transfer cash_window].include?(selected)

      if selected.start_with?("wallet_")
        profile = @citizen.bank_profiles.find_by(id: selected.delete_prefix("wallet_"))
        return profile.wallet_provider.downcase if profile&.wallet_provider.present?

        "moncash"
      elsif selected.start_with?("bank_")
        "bank_transfer"
      else
        "moncash"
      end
    end

    def extract_tax_amount(record)
      case record.record_type
      when "patente_declaration"   then record.data.dig("calcul_taxe", "total").to_f
      when "tca_declaration"       then record.data.dig("calcul_tca", "total").to_f
      when "ras_ir_declaration"    then record.data.dig("calcul_ras", "total").to_f
      when "fermage"               then record.data.dig("calcul_fermage", "total").to_f
      else 0.0 # Registration forms — fee only
      end
    end

    # ============================================================
    # Record Builders (one per form type)
    # ============================================================
    def generate_decl_number(prefix, office = "PAP")
      seq = @citizen.verification_records.where(record_type: @form_type).count + 1
      "#{prefix}-#{Time.current.year}-#{office}-#{seq.to_s.rjust(7, '0')}"
    end

    # --- NIF Registration (Formulaire A) ---
    def build_nif_registration
      auto = build_auto_fill
      decl = generate_decl_number("NIF")

      @citizen.verification_records.build(
        record_type: "nif_registration",
        status: "pending",
        data: {
          "declaration_number" => decl,
          "reference_number"   => decl,
          "filed_by"           => "citizen",
          "personne" => {
            "nom"            => params[:nom].presence || auto[:last_name],
            "prenom"         => params[:prenom].presence || auto[:first_name],
            "date_naissance" => params[:date_naissance].presence || auto[:date_of_birth]&.to_s,
            "lieu_naissance" => params[:lieu_naissance].presence || "#{auto[:birth_commune]}, #{auto[:birth_department]}",
            "sexe"           => params[:sexe].presence || auto[:sex],
            "etat_civil"     => params[:etat_civil].presence || auto[:marital_status],
            "nationalite"    => params[:nationalite].presence || auto[:nationality],
            "numero_cin"     => params[:numero_cin].presence || auto[:cin]
          },
          "adresse" => {
            "rue"         => params[:rue].presence || auto[:street_address],
            "ville"       => params[:ville].presence || auto[:locality],
            "code_postal" => params[:code_postal].presence || auto[:postal_code],
            "departement" => params[:departement].presence || auto[:birth_department],
            "commune"     => params[:commune].presence || auto[:birth_commune],
            "telephone"   => params[:telephone].presence || auto[:phone],
            "email"       => params[:email_contact].presence || auto[:email]
          },
          "activite" => {
            "type_activite"        => params[:type_activite],
            "description_activite" => params[:description_activite],
            "nom_employeur"        => params[:nom_employeur],
            "revenu_annuel"        => params[:revenu_annuel].to_f
          },
          "nif_genere"      => nil,
          "date_emission"   => Time.current.strftime("%Y-%m-%d"),
          "bureau_dgi"      => params[:bureau_dgi] || "Port-au-Prince",
          "consumption"     => { "consumed" => false }
        }
      )
    end

    # --- Business Registration (Formulaire B) ---
    # Matches official DGI Formulaire B: Sections 1-5
    def build_business_registration
      auto = build_auto_fill
      decl = generate_decl_number("ENT")

      # Build établissements array
      etablissements = []
      if params[:etablissements].is_a?(ActionController::Parameters) || params[:etablissements].is_a?(Hash)
        params[:etablissements].each_value do |etab|
          next if etab["nom_commercial"].blank? && etab["adresse"].blank?
          etablissements << etab.to_unsafe_h
        end
      end

      @citizen.verification_records.build(
        record_type: "business_registration",
        status: "pending",
        data: {
          "declaration_number" => decl,
          "reference_number"   => decl,
          "filed_by"           => "citizen",
          # Section 1 — Informations Générales
          "informations_generales" => {
            "nif"                    => params[:nif_entreprise].presence || auto[:nif],
            "numero_enregistrement"  => params[:numero_enregistrement],
            "nom_entreprise"         => params[:nom_entreprise],
            "nom_commercial"         => params[:nom_commercial],
            "date_creation"          => params[:date_creation],
            "date_debut_operations"  => params[:date_debut_operations],
            "periode_financiere"     => params[:periode_financiere],
            "nombre_employes"        => params[:nombre_employes].to_i,
            "a_patente"              => params[:a_patente],
            "numero_patente"         => params[:numero_patente],
            "exempte_tms"            => params[:exempte_tms],
            "forme_juridique"        => params[:forme_juridique],
            "chiffre_affaires"       => params[:chiffre_affaires].to_f,
            "verificateur_externe"   => params[:verificateur_externe],
            "code_secteur"           => params[:code_secteur],
            "secteur_secondaire"     => params[:secteur_secondaire],
            "objet_social"           => params[:objet_social],
            "capital_social"         => params[:capital_social].to_f
          },
          # Section 2 — Le propriétaire + Directeur
          "proprietaire" => {
            "nif"               => params[:nif_proprietaire].presence || auto[:nif],
            "prenom"            => auto[:first_name],
            "nom"               => auto[:last_name],
            "sexe"              => auto[:sex],
            "date_naissance"    => auto[:date_of_birth]&.to_s,
            "lieu_naissance"    => "#{auto[:birth_commune]}, #{auto[:birth_department]}",
            "nationalite"       => auto[:nationality]
          },
          "directeur" => {
            "nif"    => params[:nif_directeur],
            "prenom" => params[:prenom_directeur],
            "nom"    => params[:nom_directeur]
          },
          # Section 3 — Information de contact
          "contact" => {
            "telephone"        => params[:telephone].presence || auto[:phone],
            "telephone_fixe"   => params[:telephone_fixe],
            "fax"              => params[:fax],
            "email"            => params[:email_contact].presence || auto[:email],
            "email_secondaire" => params[:email_secondaire],
            "nif_comptable"    => params[:nif_comptable],
            "nom_comptable"    => params[:nom_comptable],
            "site_web"         => params[:site_web]
          },
          # Section 4 — Adresse (field 29)
          "adresse" => {
            "departement"        => params[:departement].presence || auto[:birth_department],
            "commune"            => params[:commune].presence || auto[:birth_commune],
            "section_communale"  => params[:section_communale],
            "zone"               => params[:zone],
            "rue"                => params[:rue].presence || auto[:street_address],
            "pays"               => params[:pays].presence || "Haiti",
            "info_localisation"  => params[:info_localisation]
          },
          # Section 4 — Établissements (field 30)
          "autres_etablissements" => params[:autres_etablissements],
          "etablissements"        => etablissements,
          "consumption"           => { "consumed" => false }
        }
      )
    end

    # --- Patente Declaration (DGI-F008) ---
    def build_patente_declaration
      auto = build_auto_fill
      mois = params[:mois_declaration].to_i
      decl = generate_decl_number("PAT")

      temp = VerificationRecord.new(record_type: "patente_declaration", data: {})
      calcul = temp.calculate_patente_tax(
        chiffre_affaires:       params[:chiffre_affaires],
        droit_fixe:             params[:droit_fixe],
        patente_proportionnelle: params[:patente_proportionnelle],
        montant_exoneration:    params[:montant_exoneration],
        dsav:                   params[:dsav],
        cp:                     params[:cp],
        cip:                    params[:cip],
        interets_retard:        params[:interets_retard],
        amende:                 params[:amende]
      )

      @citizen.verification_records.build(
        record_type: "patente_declaration",
        status: "pending",
        data: {
          "declaration_number" => decl,
          "filed_by"           => "citizen",
          "periode" => {
            "annee_fiscale"    => params[:annee_fiscale].presence || "#{Time.current.year}-#{Time.current.year + 1}",
            "type_declaration" => params[:type_declaration] || "originale"
          },
          "identification" => {
            "raison_sociale" => params[:raison_sociale],
            "nif"            => params[:nif_entreprise].presence || auto[:nif],
            "code_secteur"   => params[:code_secteur],
            "adresse"        => params[:adresse].presence || auto[:street_address],
            "ville"          => params[:ville].presence || auto[:locality],
            "departement"    => params[:departement].presence || auto[:birth_department],
            "commune"        => params[:commune].presence || auto[:birth_commune],
            "telephone"      => params[:telephone].presence || auto[:phone]
          },
          "calcul_taxe" => calcul,
          "paiement"    => { "methode" => "moncash" },
          "signature"   => {
            "nom_prenom"       => auto[:full_name],
            "nif_declarant"    => auto[:nif],
            "date_presentation" => Time.current.strftime("%Y-%m-%d")
          },
          "consumption" => { "consumed" => false }
        }
      )
    end

    # --- TCA Declaration ---
    def build_tca_declaration
      auto = build_auto_fill
      mois = params[:mois_declaration].to_i
      decl = generate_decl_number("TCA")

      temp = VerificationRecord.new(record_type: "tca_declaration", data: {})
      calcul = temp.calculate_tca(
        chiffre_affaires_brut:  params[:chiffre_affaires_brut],
        ventes_exonerees:       params[:ventes_exonerees],
        ventes_exportation:     params[:ventes_exportation],
        achats_locaux_tca:      params[:achats_locaux_tca],
        achats_importation_tca: params[:achats_importation_tca],
        tca_retenu_source:      params[:tca_retenu_source],
        interets_retard:        params[:interets_retard],
        amende:                 params[:amende]
      )

      @citizen.verification_records.build(
        record_type: "tca_declaration",
        status: "pending",
        data: {
          "declaration_number" => decl,
          "filed_by"           => "citizen",
          "periode" => {
            "annee_fiscale"    => params[:annee_fiscale].presence || "#{Time.current.year}-#{Time.current.year + 1}",
            "mois_declaration" => mois,
            "type_declaration" => params[:type_declaration] || "originale"
          },
          "identification" => {
            "raison_sociale" => params[:raison_sociale],
            "nif"            => params[:nif_entreprise].presence || auto[:nif],
            "adresse"        => params[:adresse].presence || auto[:street_address],
            "ville"          => params[:ville].presence || auto[:locality],
            "departement"    => params[:departement].presence || auto[:birth_department],
            "commune"        => params[:commune].presence || auto[:birth_commune],
            "telephone"      => params[:telephone].presence || auto[:phone],
            "email"          => params[:email_entreprise].presence || auto[:email],
            "numero_patente" => params[:numero_patente]
          },
          "calcul_tca" => calcul,
          "paiement"   => { "methode" => "moncash" },
          "signature"  => {
            "nom_prenom"       => auto[:full_name],
            "nif_declarant"    => auto[:nif],
            "date_presentation" => Time.current.strftime("%Y-%m-%d")
          },
          "consumption" => { "consumed" => false }
        }
      )
    end

    # --- RAS IR Declaration (DGI-F005) ---
    def build_ras_ir_declaration
      auto = build_auto_fill
      mois = params[:mois_declaration].to_i
      decl = generate_decl_number("RAS")

      employes = []
      if params[:employes].is_a?(ActionController::Parameters) || params[:employes].is_a?(Hash)
        params[:employes].each_value do |emp|
          next if emp["nom_employe"].blank?
          employes << {
            "nom_employe"  => emp["nom_employe"],
            "nif_employe"  => emp["nif_employe"],
            "salaire_brut" => emp["salaire_brut"].to_f,
            "retenue_ir"   => emp["retenue_ir"].to_f
          }
        end
      end

      temp = VerificationRecord.new(record_type: "ras_ir_declaration", data: {})
      calcul = temp.calculate_ras(
        salaires_montant:   params[:salaires_montant],
        salaires_impot:     params[:salaires_impot],
        bonis_montant:      params[:bonis_montant],
        bonis_impot:        params[:bonis_impot],
        dividendes_montant: params[:dividendes_montant],
        dividendes_impot:   params[:dividendes_impot],
        employes:           employes,
        interets_retard:    params[:interets_retard],
        amende:             params[:amende]
      )

      @citizen.verification_records.build(
        record_type: "ras_ir_declaration",
        status: "pending",
        data: {
          "declaration_number" => decl,
          "filed_by"           => "citizen",
          "periode" => {
            "annee_fiscale"    => params[:annee_fiscale].presence || "#{Time.current.year}-#{Time.current.year + 1}",
            "mois_declaration" => mois,
            "type_declaration" => params[:type_declaration] || "originale"
          },
          "identification" => {
            "raison_sociale" => params[:raison_sociale],
            "nif"            => params[:nif_entreprise].presence || auto[:nif],
            "code_secteur"   => params[:code_secteur],
            "nom_secteur"    => RecordSchemas::RasIrDeclarationSchema::SECTEUR_ACTIVITE_RAS[params[:code_secteur]&.upcase],
            "adresse"        => params[:adresse].presence || auto[:street_address],
            "ville"          => params[:ville].presence || auto[:locality],
            "departement"    => params[:departement].presence || auto[:birth_department],
            "commune"        => params[:commune].presence || auto[:birth_commune],
            "telephone"      => params[:telephone].presence || auto[:phone],
            "email"          => params[:email_entreprise].presence || auto[:email]
          },
          "employes"   => employes,
          "calcul_ras" => calcul,
          "paiement"   => { "methode" => "moncash" },
          "signature"  => {
            "nom_prenom"       => auto[:full_name],
            "nif_declarant"    => auto[:nif],
            "date_presentation" => Time.current.strftime("%Y-%m-%d")
          },
          "consumption" => { "consumed" => false }
        }
      )
    end

    # --- Fermage (DGI-55) — Land Lease Tax ---
    def build_fermage
      auto = build_auto_fill
      decl = generate_decl_number("FRM")

      droit_annuel = params[:droit_annuel].to_f
      surtaxe      = params[:surtaxe].to_f
      dtp          = params[:dtp].to_f
      solidarite   = params[:solidarite].to_f
      montant_total = droit_annuel + surtaxe + dtp + solidarite

      @citizen.verification_records.build(
        record_type: "fermage",
        status: "pending",
        data: {
          "declaration_number" => decl,
          "filed_by"           => "citizen",
          "fermier" => {
            "nom"          => params[:nom_fermier].presence || auto[:full_name],
            "demeurant_a"  => params[:demeurant_a].presence || auto[:street_address],
            "telephone"    => params[:telephone].presence || auto[:phone],
            "email"        => params[:email_contact].presence || auto[:email],
            "nif"          => params[:nif_fermier].presence || auto[:nif],
            "cin"          => params[:cin_fermier].presence || auto[:cin]
          },
          "propriete" => {
            "habitation_ou_rue" => params[:habitation_ou_rue],
            "section"           => params[:section_communale],
            "commune"           => params[:commune],
            "departement"       => params[:departement],
            "superficie"        => params[:superficie],
            "no_cadastre"       => params[:no_cadastre],
            "exercice"          => params[:exercice].presence || "#{Time.current.year}-#{Time.current.year + 1}"
          },
          "calcul_fermage" => {
            "droit_annuel"  => droit_annuel,
            "surtaxe"       => surtaxe,
            "dtp"           => dtp,
            "solidarite"    => solidarite,
            "total"         => montant_total
          },
          "paiement"   => { "methode" => "moncash" },
          "signature"  => {
            "nom_prenom"        => auto[:full_name],
            "date_presentation" => Time.current.strftime("%Y-%m-%d")
          },
          "consumption" => { "consumed" => false }
        }
      )
    end
  end
end
