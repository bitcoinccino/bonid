# app/jobs/notify_citizen_job.rb
class NotifyCitizenJob < ApplicationJob
  queue_as :default

  def perform(person_involvement_id)
    person_involvement = PersonInvolvement.find(person_involvement_id)
    return unless person_involvement.bonid.present? && person_involvement.user.present?

    # Only notify victims, witnesses, and innocent parties (not suspects/accomplices)
    # Suspects should not receive notification about investigations against them
    return unless %w[victim witness innocent].include?(person_involvement.role)

    user = person_involvement.user
    report = person_involvement.incident_report

    # Notify the citizen directly
    Citizens::CitizenMailer.with(user: user, report: report).incident_report_notification.deliver_later

    # Also notify their emergency contacts if they're a victim
    if person_involvement.role_victim?
      NotifyEmergencyContactJob.perform_later(person_involvement_id)
    end
  end
end