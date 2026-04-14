# frozen_string_literal: true

module PartnerPortal
  class NifRegistrationsController < PartnerPortal::BaseController
    before_action :set_partner
    before_action :find_record, only: [:show]

    def index
      @records = @partner.verification_records
                   .where(record_type: "nif_registration")
                   .order(created_at: :desc)

      if params[:search].present?
        search = "%#{params[:search]}%"
        @records = @records.where(
          "data->'personne'->>'nom' ILIKE :q OR data->'personne'->>'prenom' ILIKE :q OR data->'nif'->>'nif_genere' ILIKE :q",
          q: search
        )
      end
      @records = @records.where("data->'adresse'->>'departement' = ?", params[:departement]) if params[:departement].present?
      @records = @records.where("created_at >= ?", Date.parse(params[:date_from]).beginning_of_day) if params[:date_from].present?
      @records = @records.where("created_at <= ?", Date.parse(params[:date_to]).end_of_day) if params[:date_to].present?
      @records = @records.page(params[:page]).per(20)

      all = @partner.verification_records.where(record_type: "nif_registration")
      @stats = {
        total: all.count,
        today: all.where("created_at >= ?", Time.current.beginning_of_day).count
      }
    end

    def new
      @departements = RecordSchemas::NifRegistrationSchema::DEPARTEMENTS_HAITI
      @types_activite = RecordSchemas::NifRegistrationSchema::TYPES_ACTIVITE
      @etats_civils = RecordSchemas::NifRegistrationSchema::ETATS_CIVILS
      @citizen = User.find_by(bonid: params[:bonid].to_s.strip.upcase) if params[:bonid].present?
      flash.now[:alert] = "Pa jwenn sitwayen ak BonID: #{params[:bonid]}" if params[:bonid].present? && @citizen.nil?
    end

    def create
      if params[:bonid].blank?
        flash[:alert] = "BonID obligatwa."
        return redirect_to new_partner_portal_nif_registration_path
      end

      citizen = User.find_by(bonid: params[:bonid].to_s.strip.upcase)
      unless citizen
        flash[:alert] = "Pa jwenn sitwayen ak BonID: #{params[:bonid]}"
        return redirect_to new_partner_portal_nif_registration_path
      end

      office = params[:dgi_office_code].to_s.strip.presence || "PAP"
      ref_number = "NIF-#{Time.current.year}-#{office}-#{SecureRandom.hex(4).upcase}"
      generated_nif = RecordSchemas::NifRegistrationSchema.generate_nif

      record = @partner.verification_records.build(
        record_type: "nif_registration",
        user: citizen,
        status: "verified",
        verified_at: Time.current,
        data: {
          "reference_number" => ref_number,
          "personne" => {
            "nom"              => params[:nom].presence || citizen.last_name,
            "prenom"           => params[:prenom].presence || citizen.first_name,
            "date_naissance"   => params[:date_naissance].presence || citizen.dob&.to_s,
            "lieu_naissance"   => params[:lieu_naissance].presence || citizen.place_of_birth,
            "sexe"             => params[:sexe].presence || ({ "male" => "M", "female" => "F" }[citizen.sex] if citizen.sex.present?),
            "etat_civil"       => params[:etat_civil].presence || ({ "single" => "celibataire", "married" => "marie", "divorced" => "divorce", "widowed" => "veuf" }[citizen.marital_status] if citizen.marital_status.present?),
            "nationalite"      => params[:nationalite].presence || citizen.nationality || "Haitienne",
            "numero_cin"       => params[:numero_cin].presence || citizen.cin_unique_id,
            "numero_passeport" => params[:numero_passeport]
          },
          "adresse" => {
            "adresse_rue"  => params[:adresse_rue].presence || citizen.street_address,
            "ville"        => params[:ville].presence || citizen.locality,
            "departement"  => params[:departement].presence || citizen.birth_department&.name,
            "commune"      => params[:commune_name].presence || citizen.birth_commune&.name,
            "code_postal"  => params[:code_postal].presence || citizen.postal_code,
            "telephone"    => params[:telephone].presence || citizen.phone,
            "email"        => params[:email_citoyen].presence || citizen.email
          },
          "activite" => {
            "type_activite"       => params[:type_activite],
            "description_activite" => params[:description_activite],
            "nom_employeur"       => params[:nom_employeur],
            "adresse_employeur"   => params[:adresse_employeur],
            "revenu_annuel_estime" => params[:revenu_annuel_estime]
          },
          "nif" => {
            "nif_genere"     => generated_nif,
            "date_emission"  => Time.current.strftime("%Y-%m-%d"),
            "bureau_dgi"     => office
          },
          "consumption" => { "consumed" => false }
        }
      )

      if record.save
        redirect_to partner_portal_nif_registration_path(record),
                    notice: "NIF #{generated_nif} kreye avek sikse pou #{params[:prenom]} #{params[:nom]}."
      else
        flash[:alert] = record.errors.full_messages.join(", ")
        redirect_to new_partner_portal_nif_registration_path(bonid: params[:bonid])
      end
    end

    def show; end

    private

    def set_partner
      @partner = @current_partner
    end

    def find_record
      @record = @partner.verification_records.where(record_type: "nif_registration").find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to partner_portal_nif_registrations_path, alert: "Enskripsyon NIF pa jwenn."
    end
  end
end
