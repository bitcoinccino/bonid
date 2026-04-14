# frozen_string_literal: true

module PartnerPortal
  class PatenteDeclarationsController < PartnerPortal::BaseController
    before_action :set_partner
    before_action :find_record, only: [:show]

    def index
      @records = @partner.verification_records
                   .where(record_type: "patente_declaration")
                   .order(created_at: :desc)

      @records = @records.where("data->'identification'->>'raison_sociale' ILIKE :q OR data->'identification'->>'nif' ILIKE :q", q: "%#{params[:search]}%") if params[:search].present?
      @records = @records.where(status: params[:status]) if params[:status].present?
      @records = @records.where("created_at >= ?", Date.parse(params[:date_from]).beginning_of_day) if params[:date_from].present?
      @records = @records.where("created_at <= ?", Date.parse(params[:date_to]).end_of_day) if params[:date_to].present?
      @records = @records.page(params[:page]).per(20)

      all = @partner.verification_records.where(record_type: "patente_declaration")
      @stats = {
        total: all.count,
        today: all.where("created_at >= ?", Time.current.beginning_of_day).count,
        total_revenue: all.sum { |r| r.data.dig("calcul_taxe", "total").to_f }
      }
    end

    def new
      @secteurs = RecordSchemas::PatenteDeclarationSchema::SECTEUR_ACTIVITE
      @citizen = User.find_by(bonid: params[:bonid].to_s.strip.upcase) if params[:bonid].present?
      flash.now[:alert] = "Pa jwenn sitwayen ak BonID: #{params[:bonid]}" if params[:bonid].present? && @citizen.nil?
      @auto_fill = build_auto_fill(@citizen)
    end

    def create
      if params[:bonid].blank?
        flash[:alert] = "BonID obligatwa."
        return redirect_to new_partner_portal_patente_declaration_path
      end

      citizen = User.find_by(bonid: params[:bonid].to_s.strip.upcase)
      unless citizen
        flash[:alert] = "Pa jwenn sitwayen ak BonID: #{params[:bonid]}"
        return redirect_to new_partner_portal_patente_declaration_path
      end

      office = params[:dgi_office_code].to_s.strip.presence || "PAP"
      decl_number = "PAT-#{Time.current.year}-#{office}-#{SecureRandom.hex(4).upcase}"
      fiscal_year = params[:annee_fiscale].presence || "#{Time.current.year}-#{Time.current.year + 1}"

      # Build a temporary record to access the calculation method
      temp = VerificationRecord.new(record_type: "patente_declaration", data: {})
      calcul = temp.calculate_patente_tax(
        partie_fixe:      params[:partie_fixe],
        chiffre_affaires:  params[:chiffre_affaires],
        masse_salariale:   params[:masse_salariale],
        impot_deja_paye:   params[:impot_deja_paye],
        exoneration:       params[:exoneration],
        cip:               params[:cip],
        interets_retard:   params[:interets_retard],
        amende:            params[:amende]
      )

      record = @partner.verification_records.build(
        record_type: "patente_declaration",
        user: citizen,
        status: "verified",
        verified_at: Time.current,
        data: {
          "declaration_number" => decl_number,
          "periode" => {
            "annee_fiscale"    => fiscal_year,
            "mois_depot"       => params[:mois_depot].to_i,
            "type_declaration"  => params[:type_declaration] || "originale"
          },
          "identification" => {
            "raison_sociale" => params[:raison_sociale],
            "nif"            => params[:nif_entreprise],
            "adresse"        => params[:adresse].presence || citizen.street_address,
            "ville"          => params[:ville].presence || citizen.locality,
            "telephone"      => params[:telephone].presence || citizen.phone,
            "email"          => params[:email_entreprise].presence || citizen.email,
            "code_secteur"   => params[:code_secteur],
            "nom_secteur"    => RecordSchemas::PatenteDeclarationSchema::SECTEUR_ACTIVITE[params[:code_secteur]&.upcase]
          },
          "calcul_taxe" => calcul,
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
        redirect_to partner_portal_patente_declaration_path(record),
                    notice: "Deklarasyon Patant #{decl_number} kreye avek sikse."
      else
        flash[:alert] = record.errors.full_messages.join(", ")
        redirect_to new_partner_portal_patente_declaration_path(bonid: params[:bonid])
      end
    end

    def show; end

    private

    def set_partner
      @partner = @current_partner
    end

    def find_record
      @record = @partner.verification_records.where(record_type: "patente_declaration").find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to partner_portal_patente_declarations_path, alert: "Deklarasyon pa jwenn."
    end
  end
end
