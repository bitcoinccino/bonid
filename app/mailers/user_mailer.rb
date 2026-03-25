# frozen_string_literal: true

class UserMailer < Devise::Mailer
  helper :application
  include Devise::Controllers::UrlHelpers

  helper_method :invitation_url_for, :reset_url_for

  default from: "bonid@verifyem.ht", template_path: "user_mailer"
  layout "mailer"

  # ==========================================================================
  # Rails URL defaults (DO NOT override url_options as private)
  # ==========================================================================
  def default_url_options
    # Priority:
    # 1) ENV override (best for ngrok)
    # 2) ActionMailer defaults
    # 3) Rails config action_mailer defaults
    # 4) routes defaults
    opts =
      ActionMailer::Base.default_url_options.presence ||
      Rails.application.config.action_mailer.default_url_options.presence ||
      Rails.application.routes.default_url_options.presence ||
      {}

    if ENV["APP_HOST"].present?
      opts = opts.merge(
        host: ENV["APP_HOST"],
        protocol: ENV["APP_PROTOCOL"].presence || "https"
      )
      opts[:port] = ENV["APP_PORT"].to_i if ENV["APP_PORT"].present?
    end

    opts[:protocol] ||= "https"
    opts
  end

  # ==========================================================================
  # CORE: Resolve correct Devise mapping by user role
  # ==========================================================================
  def devise_mapping
    @devise_mapping ||= mapping_for(@resource)
  end

  # ==========================================================================
  # Devise Recoverable – Reset Password
  # ==========================================================================
  def reset_password_instructions(record, token, opts = {})
    @resource = record
    @token    = token

    opts[:scope] = mapping_for(record).name
    opts[:redirect_url] = reset_url_for(record, token)

    devise_mail(record, :reset_password_instructions, opts)
  end

  # ==========================================================================
  # Devise Invitable – Invitations
  # ==========================================================================
  def invitation_instructions(record, token, opts = {})
    @resource = record
    @token    = token

    opts[:scope] = mapping_for(record).name
    opts[:redirect_url] = invitation_url_for(record, token)

    devise_mail(record, :invitation_instructions, opts)
  end

  # ==========================================================================
  # URL HELPERS — Reset Password
  # ==========================================================================
  def reset_url_for(record, token)
    roles = safe_roles(record)

    if roles.include?("partner_admin")
      edit_partner_admin_password_url(reset_password_token: token)
    elsif roles.include?("officer")
      edit_officer_password_url(reset_password_token: token)
    elsif roles.any? { |r| %w[teller banking_agent].include?(r) }
      edit_banking_agent_password_url(reset_password_token: token)
    elsif roles.include?("reviewer")
      edit_reviewer_password_url(reset_password_token: token)
    elsif roles.include?("admin_user")
      edit_admin_user_password_url(reset_password_token: token)
    else
      edit_citizen_password_url(reset_password_token: token)
    end
  end

  # ==========================================================================
  # BonID Status Notifications
  # ==========================================================================
  def bonid_rejected(user, submission)
    @user = user
    @submission = submission
    @email_product = "bonid"

    mail(
      to: user.email,
      subject: "Your BonID Submission Was Rejected"
    )
  end

  def bonid_approved(user, submission)
    @user = user
    @submission = submission
    @email_product = "bonid"

    mail(
      to: user.email,
      subject: "Your BonID Has Been Approved!"
    )
  end

  # ==========================================================================
  # Name Change Request Notifications
  # ==========================================================================
  def name_change_submitted(user, name_change_request)
    @user = user
    @request = name_change_request

    mail(
      to: user.email,
      subject: "Your Name Change Request Has Been Submitted"
    )
  end

  def name_change_approved(user, name_change_request)
    @user = user
    @request = name_change_request

    mail(
      to: user.email,
      subject: "Your Name Change Has Been Approved"
    )
  end

  def name_change_rejected(user, name_change_request)
    @user = user
    @request = name_change_request

    mail(
      to: user.email,
      subject: "Your Name Change Request Was Not Approved"
    )
  end

  # ==========================================================================
  # URL HELPERS — Invitation Accept
  # Your routes show accept_* helpers exist (NOT edit_*).
  # ==========================================================================
  def invitation_url_for(record, token)
    roles = safe_roles(record)

    if roles.include?("partner_admin")
      accept_partner_admin_invitation_url(invitation_token: token)
    elsif roles.include?("officer")
      accept_officer_invitation_url(invitation_token: token)
    elsif roles.include?("reviewer")
      accept_reviewer_invitation_url(invitation_token: token)
    else
      accept_citizen_invitation_url(invitation_token: token)
    end
  rescue => e
    Rails.logger.error("[UserMailer] Invitation URL generation failed for #{record&.email}: #{e.class} #{e.message}")

    # Last-resort fallback: use the user’s mapping (safer than accept_invitation_url generic)
    mapping = mapping_for(record).name.to_s
    case mapping
    when "partner_admin" then accept_partner_admin_invitation_url(invitation_token: token)
    when "officer"       then accept_officer_invitation_url(invitation_token: token)
    when "reviewer"      then accept_reviewer_invitation_url(invitation_token: token)
    else                      accept_citizen_invitation_url(invitation_token: token)
    end
  end

  private

  def mapping_for(record)
    role_name =
      safe_roles(record).find { |role| Devise.mappings.keys.map(&:to_s).include?(role) }

    Devise.mappings[role_name&.to_sym] || Devise.mappings[:citizen]
  end

  def safe_roles(record)
    return [] unless record.respond_to?(:roles)
    record.roles.pluck(:name)
  rescue
    []
  end
end
