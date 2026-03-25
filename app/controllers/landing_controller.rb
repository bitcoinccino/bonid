# frozen_string_literal: true

class LandingController < ApplicationController
  layout "application"
  skip_before_action :authenticate_user!, raise: false

  def index
    @waitlist_signup = WaitlistSignup.new
    @departments = Department.order(:name)
    @total_signups = WaitlistSignup.count
    @launched_communes = Commune.where(launched: true).pluck(:name)
    @lang = params[:lang] == "fr" ? "fr" : "ht"
  end

  def signup
    @lang = params[:lang] == "fr" ? "fr" : "ht"

    # Bot prevention: honeypot + timestamp
    if params[:website_url].present?
      redirect_to enskri_path(lang: @lang) and return
    end
    ts = params[:signup_ts].to_i
    if ts > 0 && (Time.current.to_i - ts) < 3
      flash[:error] = t_landing("too_fast")
      redirect_to enskri_path(lang: @lang) and return
    end

    @waitlist_signup = WaitlistSignup.new(waitlist_params)

    # Check invite code if provided
    if params[:waitlist_signup][:invite_code_used].present?
      code = InviteCode.find_by(code: params[:waitlist_signup][:invite_code_used].upcase.strip)
      unless code&.valid_for_use?
        flash[:error] = t_landing("invalid_invite_code")
        redirect_to enskri_path(lang: @lang) and return
      end
    end

    if @waitlist_signup.save
      # Redeem invite code if used
      code&.redeem! if code.present?

      # Send confirmation email
      WaitlistMailer.confirmation(@waitlist_signup).deliver_later

      # Check if commune is launched or has valid invite code
      if @waitlist_signup.commune&.launched? || code.present?
        redirect_to new_user_registration_path, notice: t_landing("account_ready")
      else
        redirect_to enskri_confirmation_path(ref: @waitlist_signup.referral_code, lang: @lang)
      end
    else
      @departments = Department.order(:name)
      @total_signups = WaitlistSignup.count
      @launched_communes = Commune.where(launched: true).pluck(:name)
      render :index, status: :unprocessable_entity
    end
  end

  def confirmation
    @signup = WaitlistSignup.find_by(referral_code: params[:ref])
    redirect_to enskri_path unless @signup
    @lang = params[:lang] == "fr" ? "fr" : "ht"
    @share_url = "#{request.base_url}/enskri?ref=#{@signup.referral_code}"
    @commune_count = WaitlistSignup.where(commune_id: @signup.commune_id).count if @signup.commune_id
  end

  # AJAX: return arrondissements for a department
  def arrondissements
    arr = Arrondissement.where(department_id: params[:department_id]).order(:name)
    render json: arr.map { |a| { id: a.id, name: a.name } }
  end

  # AJAX: return communes for a department (or arrondissement)
  def communes
    if params[:department_id].present?
      communes = Commune.where(department_id: params[:department_id]).order(:name)
    elsif params[:arrondissement_id].present?
      communes = Commune.where(arrondissement_id: params[:arrondissement_id]).order(:name)
    else
      communes = Commune.none
    end
    render json: communes.map { |c|
      seed = (c.id * 7919 + 137) % 5000 + 1
      real = WaitlistSignup.where(commune_id: c.id).count
      { id: c.id, name: c.name, launched: c.launched?, signups: seed + real }
    }
  end

  private

  def waitlist_params
    params.require(:waitlist_signup).permit(
      :first_name, :last_name, :email, :phone, :signup_type,
      :commune_id, :sector, :organization_name, :invite_code_used,
      :diaspora, :country_of_residence,
      :rank, :unit_type, :unit_name
    )
  end

  def t_landing(key)
    translations = {
      "ht" => {
        "invalid_invite_code" => "Kod envitasyon sa a pa valab oswa ekspire.",
        "account_ready" => "Ou ka kreye kont ou kounye a!",
        "waitlist_success" => "Mesi! Nou pral kontakte ou le nou lanse nan zon ou.",
        "too_fast" => "Tanpri rete yon ti moman epi eseye anko."
      },
      "fr" => {
        "invalid_invite_code" => "Ce code d'invitation n'est pas valide ou a expire.",
        "account_ready" => "Vous pouvez creer votre compte maintenant!",
        "waitlist_success" => "Merci! Nous vous contacterons lors du lancement dans votre zone.",
        "too_fast" => "Veuillez patienter un moment et reessayer."
      }
    }
    translations[@lang][key] || key
  end
end
