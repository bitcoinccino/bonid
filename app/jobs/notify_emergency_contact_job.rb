# app/jobs/notify_emergency_contact_job.rb
class NotifyEmergencyContactJob < ApplicationJob
  queue_as :default

  def perform(person_involvement_id)
    person_involvement = PersonInvolvement.find_by(id: person_involvement_id)
    return unless person_involvement&.notify_emergency_contact?

    report = person_involvement.incident_report
    role = person_involvement.role

    # Only notify for victims and witnesses (not suspects/accomplices)
    return unless %w[victim witness].include?(role)

    # Handle both citizens (user_id) and tourists (visitor_submission_id)
    if person_involvement.user.present?
      notify_citizen_contacts(person_involvement, report, role)
    elsif person_involvement.visitor_submission.present?
      notify_tourist_contacts(person_involvement, report, role)
    else
      Rails.logger.warn "[EmergencyContactAlert] No user or visitor linked to person_involvement #{person_involvement_id}"
    end
  end

  private

  def notify_citizen_contacts(person_involvement, report, role)
    user = person_involvement.user

    # Get all emergency contacts for this user (with phone OR email)
    emergency_contacts = user.emergency_contacts.where(
      "phone IS NOT NULL AND phone != '' OR email IS NOT NULL AND email != ''"
    )

    emergency_contacts.each do |contact|
      send_notification(contact, user, report, role)
    end
  end

  def notify_tourist_contacts(person_involvement, report, role)
    visitor = person_involvement.visitor_submission

    # Tourists may have emergency contact info stored directly
    if visitor.emergency_contact_name.present?
      # Create a temporary contact-like object for tourists
      contact = OpenStruct.new(
        name: visitor.emergency_contact_name,
        phone: visitor.emergency_contact_phone,
        email: visitor.emergency_contact_email
      )

      # Create a user-like object for the tourist
      tourist_user = OpenStruct.new(
        first_name: visitor.first_name,
        last_name: visitor.last_name,
        full_name: [visitor.first_name, visitor.last_name].compact.join(" ")
      )

      send_notification(contact, tourist_user, report, role)
    else
      Rails.logger.info "[EmergencyContactAlert] Tourist #{visitor.bonid} has no emergency contact on file"
    end
  end

  private

  def send_notification(contact, user, report, role)
    # Send SMS if phone is available
    if contact.phone.present?
      send_sms(contact, user, report, role)
    end

    # Send email if available
    if contact.email.present?
      send_email(contact, user, report, role)
    end
  end

  def send_sms(contact, user, report, role)
    message = build_sms_message(contact, user, report, role)

    # Use Twilio or another SMS service
    # For now, log the message (implement actual SMS sending based on your SMS provider)
    Rails.logger.info "[EmergencyContactAlert] SMS to #{contact.phone}: #{message}"

    # If using Twilio:
    # TwilioService.send_sms(to: contact.phone, body: message)
  rescue => e
    Rails.logger.error "[EmergencyContactAlert] SMS failed for #{contact.phone}: #{e.message}"
  end

  def send_email(contact, user, report, role)
    Citizens::CitizenMailer.with(
      contact: contact,
      user: user,
      report: report,
      role: role
    ).emergency_contact_incident_alert.deliver_later
  rescue => e
    Rails.logger.error "[EmergencyContactAlert] Email failed for #{contact.email}: #{e.message}"
  end

  def build_sms_message(contact, user, report, role)
    role_text = role == "victim" ? "a victim" : "a witness"
    location = report.address&.commune&.name || "an unknown location"
    date = report.occurred_at&.strftime("%B %d, %Y") || "an unknown date"

    "ALERT: #{user.first_name} #{user.last_name} was reported as #{role_text} " \
    "in an incident near #{location} on #{date}. " \
    "Please contact them or the police for more information. " \
    "- BonID Emergency Alert"
  end
end
