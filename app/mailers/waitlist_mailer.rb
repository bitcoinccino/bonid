# frozen_string_literal: true

class WaitlistMailer < VerifyemMailer
  def confirmation(signup)
    @signup = signup
    @share_url = "https://bonid.ht/enskri?ref=#{signup.referral_code}"
    @commune_name = signup.commune&.name
    @commune_count = signup.commune_id ? WaitlistSignup.where(commune_id: signup.commune_id).count : 0

    mail(
      to: signup.email,
      subject: "Ou sou lis la! | You're on the list! | Vous etes inscrit!"
    )
  end

  def invitation(signup, invite_code)
    @signup = signup
    @invite_code = invite_code
    @commune_name = signup.commune&.name || "Haiti"
    @register_url = "https://bonid.ht/users/sign_up?invite=#{invite_code.code}"

    mail(
      to: signup.email,
      subject: "BonID disponib! Kreye kont ou kounye a | BonID is live!"
    )
  end
end
