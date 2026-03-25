# app/mailers/partner_portal/admin_mailer.rb
class PartnerPortal::AdminMailer < VerifyemMailer
  default from: "noreply@verifyem.ht"

  # === Partner Admin Account Created ===
  def partner_admin_account_created(user:, partner:, set_password_url:)
    @user = user
    @partner = partner
    @set_password_url = set_password_url

    mail(
      to: @user.email,
      subject: "Your BonID Partner Admin Account is Ready"
    )
  end

  # === Partner Application Approved ===
  def approved(partner:, application:)
    @partner = partner
    @application = application

    mail(
      to: @application.email,
      subject: "Your BonID Partner Application Has Been Approved"
    )
  end
end



# module Partners
#   class AdminMailer < ::ApplicationMailer
#     include Rails.application.routes.url_helpers
#     include Devise::Controllers::UrlHelpers   # Devise URLs
#     add_template_helper(PartnersHelper)       # 👈 makes invite_role_for_sector usable in views

#     default from: "partners@bonid.ht"

#     def invite(user:, token:, partner:)
#       @user       = user
#       @partner    = partner
#       @invite_url = edit_password_url(@user, reset_password_token: token)

#       mail(
#         to: @user.email,
#         subject: "You're invited to administer #{@partner.name} on BonID"
#       )
#     end

#     def approved(partner:, application:)
#       @partner     = partner
#       @application = application
#       mail(
#         to: application.email,
#         subject: "✅ #{@partner.name} – Partner Application Approved"
#       )
#     end

#     def partner_admin_account_created(user:, partner:, token:)
#       @user             = user
#       @partner          = partner
#       @set_password_url = edit_password_url(@user, reset_password_token: token)

#       mail(
#         to: @user.email,
#         subject: "Your Partner Admin Account for #{@partner.name}"
#       )
#     end

#     private

#     def default_url_options
#       Rails.application.config.action_mailer.default_url_options
#     end
#   end
# end

# # app/controllers/admin/partner_admin_invitations_controller.rb
# module Admin
#   class PartnerAdminInvitationsController < Admin::BaseController
#     before_action :set_partner

#     def option_invites
#       @partner = Partner.find(params[:partner_id])
#     end

#     def new
#       @user = User.new
#     end

#     def create
#       email     = params[:email].to_s.strip.downcase
#       user      = User.find_or_initialize_by(email: email)
#       role_name = SectorInvitationService.invite_role_for_sector(@partner.sector, role: :admin)

#       # Assign partner + fallback names
#       user.assign_attributes(
#         partner:    @partner,
#         first_name: user.first_name.presence || "Unnamed",
#         last_name:  user.last_name.presence  || role_name
#       )

#       # Ensure roles
#       user.add_role(:citizen)      unless user.has_role?(:citizen)
#       user.add_role(:partner_admin) unless user.has_role?(:partner_admin)

#       # Skip email confirmation
#       user.skip_confirmation!

#       begin
#         User.transaction do
#           if user.save(validate: false)
#             # Generate reset password token
#             raw_token, encrypted_token = Devise.token_generator.generate(User, :reset_password_token)
#             user.update!(
#               reset_password_token:   encrypted_token,
#               reset_password_sent_at: Time.current
#             )

#             # Send our custom PartnerMailer
#             Partner::LawEnforcementMailer.single_invite(user, raw_token, @partner).deliver_later

#             notice_message = user.persisted? ? "📧 Invitation sent to #{email}" : "✅ New Partner Admin invited at #{email}"
#             redirect_to admin_partners_path, notice: notice_message
#           else
#             flash.now[:alert] = "❌ Error saving user: #{user.errors.full_messages.to_sentence}"
#             render :new, status: :unprocessable_entity
#           end
#         end
#       rescue => e
#         Rails.logger.error "Exception in PartnerAdminInvitationsController#create for #{email}: #{e.message}"
#         flash.now[:alert] = "❌ An error occurred while processing the invitation for #{email}"
#         render :new, status: :unprocessable_entity
#       end
#     end

#     private

#     def set_partner
#       @partner = Partner.find(params[:partner_id])
#     end
#   end
# end
