# app/serializers/api/partner/partner_profile_serializer.rb
#
# Security: Uses UUID as the identifier — integer IDs are never exposed.
# Prevents enumeration of partners (IDOR) and hides platform scale.
#
class Api::Partner::PartnerProfileSerializer < Blueprinter::Base
  identifier :uuid

  fields :name,
         :sector,
         :email,
         :api_key_prefix,
         :sandbox_mode

  field :rate_limit do |partner|
    {
      limit: partner.rate_limit || 1000,
      remaining: partner.remaining_limit || 995
    }
  end
end
