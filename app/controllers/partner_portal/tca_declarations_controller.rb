# frozen_string_literal: true

module PartnerPortal
  class TcaDeclarationsController < PartnerPortal::BaseController
    before_action :set_partner
    before_action :find_record, only: [:show]

    def index
      @records = @partner.verification_records
                   .where(record_type: "tca_declaration")
                   .order(created_at: :desc)

      @records = @records.where("data->'identification'->>'raison_sociale' ILIKE :q OR data->'identification'->>'nif' ILIKE :q", q: "%#{params[:search]}%") if params[:search].present?
      @records = @records.where(status: params[:status]) if params[:status].present?
      @records = @records.page(params[:page]).per(20)

      all = @partner.verification_records.where(record_type: "tca_declaration")
      @stats = {
        total: all.count,
        this_month: all.where("created_at >= ?", Time.current.beginning_of_month).count,
        total_tca: all.sum { |r| r.data.dig("calcul_tca", "total").to_f }
      }
    end

    def new
      @citizen = User.find_by(bonid: params[:bonid].to_s.strip.upcase) if params[:bonid].present?
      flash.now[:alert] = "Pa jwenn sitwayen ak BonID: #{params[:bonid]}" if params[:bonid].present? && @citizen.nil?
      @auto_fill = build_auto_fill(@citizen)
    end

    def create
      if params[:bonid].blank?
        flash[:alert] = "BonID obligatwa."
        return redirect_to new_partner_portal_tca_declaration_path
      end

      citizen = User.find_by(bonid: params[:bonid].to_s.strip.upcase)
      unless citizen
        flash[:alert] = "Pa jwenn sitwayen ak BonID: #{params[:bonid]}"
        return redirect_to new_partner_portal_tca_declaration_path
      end

      office = params[:dgi_office_code].to_s.strip.presence || "PAP"
      mois = params[:mois_declaration].to_i
      decl_number = "TCA-#{Time.current.year}-#{mois.to_s.rjust(2, '0')}-#{office}-#{SecureRandom.hex(4).upcase}"
      fiscal_year = params[:annee_fiscale].presence || "#{Time.current.year}-#{Time.current.year + 1}"

      temp = VerificationRecord.new(record_type: "tca_declaration", data: {})
      calcul = temp.calculate_tca(
        chiffre_affaires_brut: params[:chiffre_affaires_brut],
        ventes_exonerees:      params[:ventes_exonerees],
        ventes_exportation:    params[:ventes_exportation],
        achats_locaux_tca:     params[:achats_locaux_tca],
        achats_importation_tca: params[:achats_importation_tca],
        tca_retenu_source:     params[:tca_retenu_source],
        interets_retard:       params[:interets_retard],
        amende:                params[:amende]
      )

      record = @partner.verification_records.build(
        record_type: "tca_declaration",
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
            "numero_patente" => params[:numero_patente]
          },
          "calcul_tca" => calcul,
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
        redirect_to partner_portal_tca_declaration_path(record),
                    notice: "Deklarasyon TCA #{decl_number} kreye avek sikse."
      else
        flash[:alert] = record.errors.full_messages.join(", ")
        redirect_to new_partner_portal_tca_declaration_path(bonid: params[:bonid])
      end
    end

    def show; end

    private

    def set_partner
      @partner = @current_partner
    end

    def find_record
      @record = @partner.verification_records.where(record_type: "tca_declaration").find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to partner_portal_tca_declarations_path, alert: "Deklarasyon pa jwenn."
    end
  end
end
