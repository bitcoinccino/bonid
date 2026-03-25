class InviteOfficerJob < ApplicationJob
  queue_as :default

  def perform(email, partner_id, first_name = nil, last_name = nil)
    partner = Partner.find_by(id: partner_id)
    return unless partner

    officer = User.find_or_initialize_by(email: email)
    officer.partner = partner
    officer.first_name ||= first_name
    officer.last_name  ||= last_name
    officer.add_role(:officer)

    # Generate Devise-compatible invitation token
    raw_token, digested_token = Devise.token_generator.generate(User, :invitation_token)
    officer.invitation_token      = digested_token
    officer.invitation_created_at = Time.current
    officer.invitation_sent_at    = Time.current

    officer.save!(validate: false)

    # Send branded officer mailer
    Officers::OfficerMailer.invitation_email(officer, raw_token).deliver_later
  end
end
