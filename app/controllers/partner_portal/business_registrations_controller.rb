# frozen_string_literal: true

module PartnerPortal
  class BusinessRegistrationsController < PartnerPortal::BaseController
    before_action :set_partner
    before_action :find_record, only: [:show]

    def index
      @records = @partner.verification_records
                   .where(record_type: "business_registration")
                   .order(created_at: :desc)

      if params[:search].present?
        search = "%#{params[:search]}%"
        @records = @records.where(
          "data->'informations_generales'->>'raison_sociale' ILIKE :q OR data->'proprietaire'->>'nom' ILIKE :q OR data->'proprietaire'->>'prenom' ILIKE :q",
          q: search
        )
      end
      @records = @records.where("data->'adresse'->>'departement' = ?", params[:departement]) if params[:departement].present?
      @records = @records.where("created_at >= ?", Date.parse(params[:date_from]).beginning_of_day) if params[:date_from].present?
      @records = @records.where("created_at <= ?", Date.parse(params[:date_to]).end_of_day) if params[:date_to].present?
      @records = @records.page(params[:page]).per(20)

      all = @partner.verification_records.where(record_type: "business_registration")
      @stats = {
        total: all.count,
        today: all.where("created_at >= ?", Time.current.beginning_of_day).count
      }
    end

    def new
      @departements = RecordSchemas::NifRegistrationSchema::DEPARTEMENTS_HAITI
      @secteurs = RecordSchemas::BusinessRegistrationSchema::SECTEUR_ACTIVITE_BIZ
      @citizen = User.find_by(bonid: params[:bonid].to_s.strip.upcase) if params[:bonid].present?
      flash.now[:alert] = "Pa jwenn sitwayen ak BonID: #{params[:bonid]}" if params[:bonid].present? && @citizen.nil?
      @auto_fill = build_auto_fill(@citizen)
    end

    def create
      if params[:bonid].blank?
        flash[:alert] = "BonID obligatwa."
        return redirect_to new_partner_portal_business_registration_path
      end

      citizen = User.find_by(bonid: params[:bonid].to_s.strip.upcase)
      unless citizen
        flash[:alert] = "Pa jwenn sitwayen ak BonID: #{params[:bonid]}"
        return redirect_to new_partner_portal_business_registration_path
      end

      office = params[:dgi_office_code].to_s.strip.presence || "PAP"
      ref_number = "ENT-#{Time.current.year}-#{office}-#{SecureRandom.hex(4).upcase}"

      # Parse etablissements (up to 5 additional locations)
      etablissements = []
      if params[:etablissements].is_a?(ActionController::Parameters) || params[:etablissements].is_a?(Hash)
        params[:etablissements].each_value do |etab|
          next if etab["adresse"].blank? && etab["nom_commercial"].blank?
          etablissements << {
            "nom_commercial"    => etab["nom_commercial"],
            "adresse"           => etab["adresse"],
            "zone"              => etab["zone"],
            "departement"       => etab["departement"],
            "commune"           => etab["commune"],
            "section_communale" => etab["section_communale"],
            "pays"              => etab["pays"].presence || "Haiti"
          }
        end
      end

      record = @partner.verification_records.build(
        record_type: "business_registration",
        user: citizen,
        status: "verified",
        verified_at: Time.current,
        data: {
          "reference_number" => ref_number,
          # Section 1 — Informations Generales
          "informations_generales" => {
            "nif"                           => params[:nif_entreprise],
            "numero_enregistrement"         => ref_number,
            "raison_sociale"                => params[:raison_sociale],
            "nom_commercial"                => params[:nom_commercial],
            "date_creation"                 => params[:date_creation],
            "date_debut_operations"         => params[:date_debut_operations],
            "periode_financiere"            => params[:periode_financiere],
            "nombre_employes"               => params[:nombre_employes].to_i,
            "a_patente"                     => params[:a_patente] == "1",
            "numero_patente"                => params[:numero_patente],
            "exempte_taxe_masse_salariale"  => params[:exempte_tms],
            "nationalite_entreprise"        => params[:nationalite_entreprise],
            "sexe_proprietaire"             => ({ "male" => "M", "female" => "F" }[citizen.sex] if citizen.sex.present?),
            "chiffre_affaires"              => params[:chiffre_affaires],
            "verificateur_externe"          => params[:verificateur_externe] == "1",
            "secteur_activite_primaire"     => params[:secteur_primaire],
            "secteurs_activite_secondaires" => params[:secteurs_secondaires]
          },
          # Section 2 — Le Proprietaire
          "proprietaire" => {
            "nif"               => params[:nif_proprietaire],
            "prenom"            => params[:prenom_proprietaire].presence || citizen.first_name,
            "nom"               => params[:nom_proprietaire].presence || citizen.last_name,
            "nif_directeur"     => params[:nif_directeur],
            "prenom_directeur"  => params[:prenom_directeur],
            "nom_directeur"     => params[:nom_directeur]
          },
          # Section 3 — Information de Contact
          "contact" => {
            "telephone_mobile"  => params[:telephone_mobile].presence || citizen.phone,
            "telephone_fixe"    => params[:telephone_fixe],
            "fax"               => params[:fax],
            "email_primaire"    => params[:email_primaire].presence || citizen.email,
            "email_secondaire"  => params[:email_secondaire],
            "nif_comptable"     => params[:nif_comptable],
            "nom_comptable"     => params[:nom_comptable]
          },
          # Section 4 — Adresse (field 29)
          "adresse" => {
            "departement"       => params[:departement].presence || citizen.birth_department&.name,
            "commune"           => params[:commune_name].presence || citizen.birth_commune&.name,
            "section_communale" => params[:section_communale],
            "zone"              => params[:zone],
            "adresse"           => params[:adresse_rue].presence || citizen.street_address,
            "pays"              => params[:pays].presence || citizen.country || "Haiti",
            "info_additionnelle" => params[:info_localisation]
          },
          # Section 4 — Etablissements (field 30)
          "etablissements" => etablissements,
          # Section 5 — Certification
          "certification" => {
            "nom"  => params[:certifie_par].presence || "#{citizen.first_name} #{citizen.last_name}",
            "date" => Time.current.strftime("%Y-%m-%d")
          },
          "consumption" => { "consumed" => false }
        }
      )

      if record.save
        redirect_to partner_portal_business_registration_path(record),
                    notice: "Anrejistreman biznis #{ref_number} kreye avek sikse pou #{params[:raison_sociale]}."
      else
        flash[:alert] = record.errors.full_messages.join(", ")
        redirect_to new_partner_portal_business_registration_path(bonid: params[:bonid])
      end
    end

    def show; end

    private

    def set_partner
      @partner = @current_partner
    end

    def find_record
      @record = @partner.verification_records.where(record_type: "business_registration").find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to partner_portal_business_registrations_path, alert: "Anrejistreman biznis pa jwenn."
    end
  end
end
