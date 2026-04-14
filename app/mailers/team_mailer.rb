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

  # Suspension notice — sent when a team member is suspended
  def suspended(user:, partner:, reason: nil)
    @user    = user
    @partner = partner
    @reason  = reason

    mail(
      to:      user.email,
      subject: "BonID: Kont Sispann — #{partner.name}"
    )
  end

  # Reactivation notice — sent when a suspended member is reactivated
  def reactivated(user:, partner:)
    @user    = user
    @partner = partner

    mail(
      to:      user.email,
      subject: "BonID: Kont Reaktive — #{partner.name}"
    )
  end

  # Role granted notification — for internal staff (reviewers, etc.)
  # No partner context, no invitation token. The user already has BonID credentials.
  # They just need to know their role was upgraded and where to sign in.
  #
  # @param user [User]   the person who was granted the role
  # @param role [String] "reviewer" (extensible for future internal roles)
  def role_granted(user:, role:)
    @user = user
    @role = role
    @role_label = role.humanize
    @sign_in_url = new_reviewer_session_url

    mail(
      to:      user.email,
      subject: "BonID: Ou se yon #{@role_label} kounye a"
    )
  end

  private
end
