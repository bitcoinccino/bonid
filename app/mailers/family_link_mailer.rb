# frozen_string_literal: true

class FamilyLinkMailer < ApplicationMailer
  default from: "bonid@verifyem.ht"
  layout "mailer_citizen"

  # Two-Way Shake: asks the parent to confirm the relationship
  # "Marie di ou se Manman li. Èske se vre?"
  def confirm_relationship(family_member)
    @family_member = family_member
    @citizen = family_member.user
    @relative = family_member.linked_user
    @relationship = family_member.display_relationship
    @token = family_member.link_consent_token

    @confirm_url = confirm_family_link_url(token: @token)
    @deny_url = deny_family_link_url(token: @token)

    mail(
      to: @relative.email,
      subject: "Konfimasyon Relasyon Fanmi - BonID"
    )
  end
end
