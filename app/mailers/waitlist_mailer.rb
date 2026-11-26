# frozen_string_literal: true

# Waitlist emails. Links use the route helpers + the environment's
# default_url_options (never a hard-coded domain), and carry the green light
# that opens /signup: ?commune=<code> or ?invite=<code>.
class WaitlistMailer < VerifyemMailer
  def confirmation(signup)
    @signup = signup
    @share_url = enskri_url(ref: signup.referral_code)
    @commune_name = signup.commune&.name
    @commune_count = signup.commune_id ? WaitlistSignup.where(commune_id: signup.commune_id).count : 0

    mail(
      to: signup.email,
      subject: "Ou sou lis la! | You're on the list! | Vous etes inscrit!"
    )
  end

  # Sent to everyone still waiting when an admin launches their commune.
  def commune_launched(signup)
    @signup = signup
    @commune_name = signup.commune&.name || "Haiti"
    @register_url = signup_url(commune: signup.commune&.code)

    mail(
      to: signup.email,
      subject: "BonID disponib nan #{@commune_name}! | BonID is live in #{@commune_name}!"
    )
  end

  # Sent when an admin invites one person (or a batch) from the waitlist.
  def invitation(signup, invite_code)
    @signup = signup
    @invite_code = invite_code
    @commune_name = signup.commune&.name || "Haiti"
    @register_url = signup_url(invite: invite_code.code)

    mail(
      to: signup.email,
      subject: "BonID disponib! Kreye kont ou kounye a | BonID is live!"
    )
  end
end
