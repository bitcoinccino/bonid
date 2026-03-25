class OfficerPasswordPolicy
  def initialize(officer)
    @officer = officer
  end

  def recently_confirmed?
    return false unless @officer.password_confirmed_at.present?
    @officer.password_confirmed_at > 10.minutes.ago
  end
end
