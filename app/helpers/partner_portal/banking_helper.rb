# app/helpers/partner_portal/banking_helper.rb
module PartnerPortal::BankingHelper
  # ✅ Checks if either a Partner Admin or a Teller (Banking Agent) is signed in
  def banking_user_signed_in?
    partner_admin_signed_in? || banking_agent_signed_in?
  end

  # ✅ Returns whichever is currently logged in (Partner Admin or Teller)
  def current_banking_user
    current_partner_admin || current_banking_agent
  end
end
