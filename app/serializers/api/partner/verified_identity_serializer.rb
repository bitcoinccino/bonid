# app/serializers/api/partner/verified_identity_serializer.rb
# app/serializers/api/partner/verified_identity_serializer.rb
class Api::Partner::VerifiedIdentitySerializer < Blueprinter::Base
  view :partner do
    association :user, blueprint: CitizenSummarySerializer
    association :verification, blueprint: Api::Partner::IdentitySubmissionPartnerViewSerializer
  end
end
