# app/serializers/api/partner/identity_submission_partner_view_serializer.rb
class Api::Partner::IdentitySubmissionPartnerViewSerializer < Api::Partner::IdentitySubmissionBaseSerializer
  fields :qr_public_url,
         :verified_by,
         :partner
end
