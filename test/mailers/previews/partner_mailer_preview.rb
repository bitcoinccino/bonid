class PartnerMailerPreview < ActionMailer::Preview
  def approved
    partner = Partner.verified.first || Partner.last
    PartnerMailer.approved(partner)
  end
end
