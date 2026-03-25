# frozen_string_literal: true

# TeamMailer
# ==========
# Unified mailer for all team invitations across every partner sector.
# One template, dynamic content based on role + sector.

class TeamMailer < ApplicationMailer
  default from: "noreply@bonid.ht"
  layout "mailer"

  # Invitation email — sent when a partner admin invites a team member
  #
  # @param user    [User]    the invitee (must have verified BonID)
  # @param partner [Partner] the partner organization
  # @param role    [String]  "partner_admin" or "partner_agent"
  # @param token   [String]  raw Devise invitation token
  def invitation(user:, partner:, role:, token:)
    @user    = user
    @partner = partner
    @role    = role
    @token   = token

    sector = partner.department_sector || partner.sector
    @role_label = GovernmentRoleConstants.role_label(sector, role)
    @sector_label = PartnerSectorConstants.human_sector_label(sector)

    @accept_url = accept_team_invitation_url(invitation_token: token)

    mail(
      to:      user.email,
      subject: "BonID: Envitasyon Ekip — #{partner.name} (#{@role_label})"
    )
  end

  # Revocation notice — sent when a team member is removed
  def revoked(user:, partner:, role:)
    @user    = user
    @partner = partner
    sector = partner.department_sector || partner.sector
    @role_label = GovernmentRoleConstants.role_label(sector, role)

    mail(
      to:      user.email,
      subject: "BonID: Aksè Retire — #{partner.name}"
    )
  end

  private
end
