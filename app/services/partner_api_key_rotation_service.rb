# frozen_string_literal: true

class PartnerApiKeyRotationService
  def initialize(partner, admin_user)
    @partner = partner
    @admin_user = admin_user
  end

  def rotate!
    @partner.rotate_api_key!
  end
end
