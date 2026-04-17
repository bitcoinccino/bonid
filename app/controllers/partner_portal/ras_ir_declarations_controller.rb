# frozen_string_literal: true

module PartnerPortal
  class RasIrDeclarationsController < PartnerPortal::BaseController
    before_action :set_partner
    before_action :find_record, only: [ :show ]

    def index
      @records = @partner.verification_records
                   .where(record_type: "ras_ir_declaration")
                   .order(created_at: :desc)

      @records = @records.where("data->'identification'->>'raison_sociale' ILIKE :q OR data->'identification'->>'nif' ILIKE :q", q: "%#{params[:search]}%") if params[:search].present?
      @records = @records.where(status: params[:status]) if params[:status].present?
      @records = @records.page(params[:page]).per(20)

      all = @partner.verification_records.where(record_type: "ras_ir_declaration")
      @stats = {
        total: all.count,
        this_month: all.where("created_at >= ?", Time.current.beginning_of_month).count,
        total_withheld: all.sum { |r| r.data.dig("calcul_ras", "total").to_f }
      }
    end

    def new
      @tranches = RecordSchemas::RasIrDeclarationSchema::TRANCHES_IR
      @secteurs = RecordSchemas::RasIrDeclarationSchema::SECTEUR_ACTIVITE_RAS
      @citizen = User.find_by(bonid: params[:bonid].to_s.strip.upcase) if params[:bonid].present?
      flash.now[:alert] = "Pa jwenn sitwayen ak BonID: #{params[:bonid]}" if params[:bonid].present? && @citizen.nil?
      @auto_fill = build_auto_fill(@citizen)
    end

    def create
      if params[:bonid].blank?
        flash[:alert] = "BonID obligatwa."
        return redirect_to new_partner_portal_ras_ir_declaration_path
      end

      citizen = User.find_by(bonid: params[:bonid].to_s.strip.upcase)
      unless citizen
        flash[:alert] = "Pa jwenn sitwayen ak BonID: #{params[:bonid]}"
        return redirect_to new_partner_portal_ras_ir_declaration_path
      end

      office = params[:dgi_office_code].to_s.strip.presence || "PAP"
      mois = params[:mois_declaration].to_i
      decl_number = "RAS-#{Time.current.year}-#{mois.to_s.rjust(2, '0')}-#{office}-#{SecureRandom.hex(4).upcase}"
      fiscal_year = params[:annee_fiscale].presence || "#{Time.current.year}-#{Time.current.year + 1}"

      # Parse employee list from params (Line 11 — Annexe)
      employes = []
      if params[:employes].is_a?(ActionController::Parameters) || params[:employes].is_a?(Hash)
        params[:employes].each_value do |emp|
          next if emp["nom_employe"].blank?
          employes << {
            "nom_employe"   => emp["nom_employe"],
            "nif_employe"   => emp["nif_employe"],
            "salaire_brut"  => emp["salaire_brut"].to_f,
            "retenue_ir"    => emp["retenue_ir"].to_f
          }
        end
      end

      temp = VerificationRecord.new(record_type: "ras_ir_declaration", data: {})
      calcul = temp.calculate_ras(
        salaires_montant:    params[:salaires_montant],
        salaires_impot:      params[:salaires_impot],
        bonis_montant:       params[:bonis_montant],
        bonis_impot:         params[:bonis_impot],
        dividendes_montant:  params[:dividendes_montant],
        dividendes_impot:    params[:dividendes_impot],
        employes:            employes,
        interets_retard:     params[:interets_retard],
        amende:              params[:amende]
      )

      record = @partner.verification_records.build(
        record_type: "ras_ir_declaration",
        user: citizen,
        status: "verified",
        verified_at: Time.current,
        data: {
          "declaration_number" => decl_number,
          "periode" => {
            "annee_fiscale"    => fiscal_year,
            "mois_declaration" => mois,
            "type_declaration" => params[:type_declaration] || "originale"
          },
          "identification" => {
            "raison_sociale" => params[:raison_sociale],
            "nif"            => params[:nif_entreprise],
            "adresse"        => params[:adresse].presence || citizen.street_address,
            "ville"          => params[:ville].presence || citizen.locality,
            "telephone"      => params[:telephone].presence || citizen.phone,
            "email"          => params[:email_entreprise].presence || citizen.email,
            "code_secteur"   => params[:code_secteur],
            "nom_secteur"    => RecordSchemas::RasIrDeclarationSchema::SECTEUR_ACTIVITE_RAS[params[:code_secteur]&.upcase]
          },
          "employes" => employes,
          "calcul_ras" => calcul,
          "paiement" => {
            "methode"        => params[:methode_paiement],
            "numero_cheque"  => params[:numero_cheque],
            "banque"         => params[:banque]
          },
          "signature" => {
            "nom_prenom"       => params[:declarant_nom],
            "nif_declarant"    => params[:declarant_nif],
            "date_presentation" => Time.current.strftime("%Y-%m-%d")
          },
          "consumption" => { "consumed" => false }
        }
      )

      if record.save
        redirect_to partner_portal_ras_ir_declaration_path(record),
                    notice: "Deklarasyon RAS IR #{decl_number} kreye avek sikse."
      else
        flash[:alert] = record.errors.full_messages.join(", ")
        redirect_to new_partner_portal_ras_ir_declaration_path(bonid: params[:bonid])
      end
    end

    def show; end

    private

    def set_partner
      @partner = @current_partner
    end

    def find_record
      @record = @partner.verification_records.where(record_type: "ras_ir_declaration").find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to partner_portal_ras_ir_declarations_path, alert: "Deklarasyon pa jwenn."
    end
  end
end
