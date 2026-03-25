# frozen_string_literal: true

# Two-Way Shake: When Marie adds her mother via BonID,
# the mother gets a notification asking to confirm the relationship.
#
# "Marie Jean-Baptiste di se pitit ou li ye. Èske se vre?"
#
class NotifyFamilyLinkJob < ApplicationJob
  queue_as :default
  retry_on ActiveRecord::ConnectionNotEstablished, wait: 5.seconds, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  def perform(family_member_id:)
    fm = FamilyMember.find(family_member_id)
    return unless fm.linked_user.present?
    return if fm.link_confirmed?

    # Generate consent token for the linked person to confirm
    fm.request_link_consent!

    citizen = fm.user
    relative = fm.linked_user
    relationship_label = fm.display_relationship

    # Send notification to the linked person
    # (SMS, push, or in-app — depending on what's available)
    message = "#{citizen.first_name} #{citizen.last_name} di ou se #{relationship_label} li. Èske se vre?"

    if relative.phone.present?
      # SMS notification
      Rails.logger.info("[FamilyLink] SMS to #{relative.phone}: #{message}")
      # TODO: Integrate with SMS provider (Twilio, Digicel API)
      # SmsService.send(to: relative.phone, body: message)
    end

    if relative.email.present?
      FamilyLinkMailer.confirm_relationship(fm).deliver_later
      Rails.logger.info("[FamilyLink] Email sent to #{relative.email}: #{message}")
    end

    # Update status to pending
    fm.update!(verification_status: :pending_confirmation) if fm.manual_entry?

    Rails.logger.info("[FamilyLink] Notification sent for FamilyMember##{fm.id}: #{citizen.bonid} → #{relative.bonid}")
  end
end
