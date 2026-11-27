# frozen_string_literal: true

# Waitlist emails. Links use the route helpers + the environment's
# default_url_options (never a hard-coded domain), and carry the green light
# that opens /signup: ?commune=<code> or ?invite=<code>.
class WaitlistMailer < VerifyemMailer
  # The waitlist is for BonID: BonID header and footer, like citizen emails
  # (sender stays noreply@verifyem.ht).
  before_action { @email_product = "bonid" }

  # Sent in the language the person signed up in.
  def confirmation(signup)
    @signup = signup
    @share_url = enskri_url(ref: signup.referral_code, lang: nil)
    @commune_name = signup.commune&.name
    @commune_count = signup.commune_id ? WaitlistSignup.where(commune_id: signup.commune_id).count : 0

    I18n.with_locale(signup.email_locale) do
      mail(to: signup.email, subject: t("mailers.waitlist_confirmation.subject"))
    end
  end

  # Sent to everyone still waiting when an admin launches their commune.
  def commune_launched(signup)
    @signup = signup
    @commune_name = signup.commune&.name
    @register_url = signup_url(commune: signup.commune&.code, lang: signup.email_locale)

    I18n.with_locale(signup.email_locale) do
      mail(to: signup.email, subject: t("mailers.waitlist_launch.subject", commune: @commune_name))
    end
  end

  # Sent when an admin invites one person (or a batch) from the waitlist.
  def invitation(signup, invite_code)
    @signup = signup
    @invite_code = invite_code
    @commune_name = signup.commune&.name
    @register_url = signup_url(invite: invite_code.code, lang: signup.email_locale)

    I18n.with_locale(signup.email_locale) do
      mail(to: signup.email, subject: t("mailers.waitlist_invitation.subject"))
    end
  end
end
