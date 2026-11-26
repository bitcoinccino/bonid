# frozen_string_literal: true

class LandingController < ApplicationController
  layout "application"
  skip_before_action :authenticate_user!, raise: false

  def index
    @waitlist_signup = WaitlistSignup.new
    # Share link (/enskri?ref=CODE): open the form with "Invited by <name>"
    @referrer = WaitlistSignup.find_by_referral_code(params[:ref]) if params[:ref].present?
    @waitlist_signup.referred_by_code = @referrer&.referral_code
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
    @waitlist_signup.locale = I18n.locale.to_s # emails go out in this language

    # Check invite code if provided. It is redeemed on /signup once the
    # account exists, not here.
    if params[:waitlist_signup][:invite_code_used].present?
      code = InviteCode.find_available(params[:waitlist_signup][:invite_code_used])
      return render_enskri_error(t_landing("invalid_invite_code")) unless code
    end

    if @waitlist_signup.save
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
        enskri_redirect(account_signup_path(@waitlist_signup, code), t_landing("account_ready"))
      else
        # Full locale (en/fr/ht): the confirmation page is translated in all three
        enskri_redirect(enskri_confirmation_path(ref: @waitlist_signup.referral_code, lang: I18n.locale))
      end
    else
      # Surface the validation error (e.g. duplicate email) in place on the
      # wizard — modal stays open, the user's input is preserved.
      message =
        if @waitlist_signup.errors.of_kind?(:email, :taken)
          t_landing("email_taken")
        else
          @waitlist_signup.errors.map(&:message).uniq.to_sentence.presence || t_landing("waitlist_error")
        end
      render_enskri_error(message)
    end
  end

  def confirmation
    @signup = WaitlistSignup.find_by(referral_code: params[:ref])
    return redirect_to enskri_path unless @signup

    # Rendered in the visitor's locale (en/fr/ht via set_locale)
    @share_url = enskri_url(ref: @signup.referral_code, lang: nil)
    @commune = @signup.commune
    @commune_count = @commune ? @commune.display_signups : WaitlistSignup.count
    @masked_email = mask_email(@signup.email)
    @referrals_count = @signup.referrals.count

    # Standalone full-screen success page — render without the marketing chrome.
    render layout: "blank"
  end

  # AJAX: return arrondissements for a department
  def arrondissements
    arr = Arrondissement.where(department_id: params[:department_id]).order(:name)
    render json: arr.map { |a| { id: a.id, name: a.name } }
  end

  # AJAX: city suggestions for a US state (curated first, then every Census
  # place). Static data, so browsers may cache it.
  def us_cities
    expires_in 1.day, public: true
    render json: DiasporaLocations.cities_for(params[:state]).to_json
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

  # r***d@yahoo.com — enough for the person to recognize their address
  def mask_email(email)
    local, domain = email.to_s.split("@", 2)
    return email if domain.blank?

    masked = local.length <= 2 ? "#{local[0]}***" : "#{local[0]}***#{local[-1]}"
    "#{masked}@#{domain}"
  end

  # Where an individual goes once they may create an account: /signup
  # carrying the green light that let them in (their invite code, or their
  # launched commune).
  def account_signup_path(signup, code)
    if code
      signup_path(lang: @lang, invite: code.code)
    else
      signup_path(lang: @lang, commune: signup.commune.code)
    end
  end

  # Error response for a failed signup. JSON for the wizard's in-place fetch
  # (modal stays open, no reload); HTML redirect + flash as a no-JS fallback.
  # A nil message clears the banner (used for the silent honeypot).
  def render_enskri_error(message)
    respond_to do |format|
      format.json { render json: { ok: false, error: message } }
      format.html do
        # Dedicated key so the global flash toast doesn't ALSO show it — the
        # wizard's own banner renders it (see landing/index + _enskri_error).
        flash[:enskri_error] = message if message.present?
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
      :diaspora, :country_of_residence, :residence_state, :residence_city, :referred_by_code,
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
        "too_fast" => "Tanpri rete yon ti moman epi eseye ankò.",
        "email_taken" => "Imèl sa a enskri deja."
      },
      "fr" => {
        "invalid_invite_code" => "Ce code d'invitation n'est pas valide ou a expiré.",
        "account_ready" => "Vous pouvez créer votre compte maintenant !",
        "partner_next" => "Configurons votre organisation — complétez votre demande de partenaire.",
        "waitlist_success" => "Merci ! Nous vous contacterons lors du lancement dans votre zone.",
        "waitlist_error" => "Une erreur s'est produite. Veuillez vérifier vos informations et réessayer.",
        "too_fast" => "Veuillez patienter un moment et réessayer.",
        "email_taken" => "Cet e-mail est déjà inscrit."
      }
    }
    translations[@lang][key] || key
  end
end
