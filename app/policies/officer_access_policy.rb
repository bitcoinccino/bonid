# app/policies/officer_access_policy.rb
class OfficerAccessPolicy
  ALLOWED_SLUGS = [ "pnh", "police-nationale-dhaiti" ].freeze

  def initialize(officer)
    @officer = officer
  end

  def authorize!
    raise Pundit::NotAuthorizedError, "🚫 Officers only" unless @officer

    partner = @officer.partner
    unless partner&.sector == "law_enforcement" &&
           ALLOWED_SLUGS.include?(partner.slug&.downcase&.strip)
      raise Pundit::NotAuthorizedError, "🚫 Access restricted to PNH officers"
    end

    true
  end
end
