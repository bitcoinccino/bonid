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

    # Bot prevention: honeypot + timestamp. Silently no-op for the honeypot;
    # surface a friendly message for the too-fast case — both in-place so the
    # wizard modal stays open.
    if params[:website_url].present?
      return render_enskri_error(nil)
    end
    ts = params[:signup_ts].to_i
    if ts > 0 && (Time.current.to_i - ts) < 3
      return render_enskri_error(t_landing("too_fast"))
    end

    @waitlist_signup = WaitlistSignup.new(waitlist_params)

    # Check invite code if provided
    if params[:waitlist_signup][:invite_code_used].present?
      code = InviteCode.find_by(code: params[:waitlist_signup][:invite_code_used].upcase.strip)
      unless code&.valid_for_use?
        return render_enskri_error(t_landing("invalid_invite_code"))
      end
    end

    if @waitlist_signup.save
      # Redeem invite code if used
      code&.redeem! if code.present?

      # Organizations don't roll out by commune — hand them off to the partner
      # application pipeline (vetting/approval) instead of the geographic gate.
      if @waitlist_signup.signup_type == "business"
        return enskri_redirect(
          new_partner_path(
            org: @waitlist_signup.organization_name,
            email: @waitlist_signup.email,
            sector: @waitlist_signup.sector,
            lead: @waitlist_signup.id
          ),
          t_landing("partner_next")
        )
      end

      # Individuals: confirmation email + geographic launch gate
      WaitlistMailer.confirmation(@waitlist_signup).deliver_later

      # Check if commune is launched or has valid invite code
      if @waitlist_signup.commune&.launched? || code.present?
        enskri_redirect(new_user_registration_path, t_landing("account_ready"))
      else
        enskri_redirect(enskri_confirmation_path(ref: @waitlist_signup.referral_code, lang: @lang))
      end
    else
      # Surface the validation error (e.g. duplicate email) in place on the
      # wizard — modal stays open, the user's input is preserved.
      render_enskri_error(
        @waitlist_signup.errors.map(&:message).uniq.to_sentence.presence ||
        t_landing("waitlist_error")
      )
    end
  end

  def confirmation
    @signup = WaitlistSignup.find_by(referral_code: params[:ref])
    redirect_to enskri_path unless @signup
    @lang = params[:lang] == "fr" ? "fr" : "ht"
    @share_url = "#{request.base_url}/enskri?ref=#{@signup.referral_code}"
    @commune_count = @signup.commune.display_signups if @signup.commune
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
    payload = communes.map { |c|
      { id: c.id, name: c.name, launched: c.launched?, signups: c.display_signups }
    }
    # Render pre-serialized JSON so active_model_serializers doesn't try
    # (and fail) to find a serializer for these plain hashes.
    render json: payload.to_json
  end

  private

  # Error response for a failed signup. JSON for the wizard's in-place fetch
  # (modal stays open, no reload); HTML redirect + flash as a no-JS fallback.
  # A nil message clears the banner (used for the silent honeypot).
  def render_enskri_error(message)
    respond_to do |format|
      format.json { render json: { ok: false, error: message } }
      format.html do
        flash[:error] = message if message.present?
        redirect_to enskri_path(lang: @lang)
      end
    end
  end

  # Success response. JSON tells the wizard where to navigate; HTML redirects.
  def enskri_redirect(url, notice = nil)
    respond_to do |format|
      format.json { render json: { ok: true, redirect: url } }
      format.html do
        flash[:notice] = notice if notice
        redirect_to url
      end
    end
  end

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
        "partner_next" => "Ann konfigire òganizasyon ou — ranpli aplikasyon patnè a.",
        "waitlist_success" => "Mesi! Nou pral kontakte ou le nou lanse nan zon ou.",
        "waitlist_error" => "Gen yon erè. Tanpri tcheke enfòmasyon ou yo epi eseye ankò.",
        "too_fast" => "Tanpri rete yon ti moman epi eseye anko."
      },
      "fr" => {
        "invalid_invite_code" => "Ce code d'invitation n'est pas valide ou a expire.",
        "account_ready" => "Vous pouvez creer votre compte maintenant!",
        "partner_next" => "Configurons votre organisation — completez votre demande de partenaire.",
        "waitlist_success" => "Merci! Nous vous contacterons lors du lancement dans votre zone.",
        "waitlist_error" => "Une erreur s'est produite. Veuillez verifier vos informations et reessayer.",
        "too_fast" => "Veuillez patienter un moment et reessayer."
      }
    }
    translations[@lang][key] || key
  end
end
