class PartnerMailerPreview < ActionMailer::Preview
  def approved
    partner = Partner.last || Partner.first
    PartnerMailer.approved(partner)
  end

  def partner_admin_account_created
    user = User.where(role_int: User.role_ints[:partner_admin]).last || User.last
    partner = user.partner || Partner.last

    PartnerMailer.partner_admin_account_created(
      user,
      partner: partner,
      password: "Secret1234",
      reset_url: "http://localhost:3000/users/password/edit?reset_password_token=dummytoken"
    )
  end
end
