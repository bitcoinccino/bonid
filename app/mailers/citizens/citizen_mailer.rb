module Citizens
  class CitizenMailer < Citizens::BaseMailer
    default from: "bonid@verifyem.ht"
    layout "mailer"

    def otp_login
      raw_user = params[:user]
      @user = raw_user.is_a?(CitizenProfile) ? raw_user.user : raw_user
      @otp  = params[:otp]
      @email_product = "bonid"

      mail(
        to: @user.email,
        subject: "BonID: Kòd Koneksyon Ou"
      )
    end

    def incident_report_notification
      raw_user = params[:user]
      @user   = raw_user.is_a?(CitizenProfile) ? raw_user.user : raw_user
      @report = params[:report]
      @email_product = "bonid"

      mail(
        to: @user.email,
        subject: "BonID: Notifikasyon Rapò Ensidan"
      )
    end

    # Notify a BonID holder that they've been added as an emergency contact
    def emergency_contact_added
      @contact_user = params[:contact_user]  # The BonID holder being added
      @added_by     = params[:added_by]       # The citizen who added them
      @relation     = params[:relation]       # e.g., "sibling", "parent"
      @email_product = "bonid"

      mail(
        to: @contact_user.email,
        subject: "BonID: Ou ajoute kòm Kontak Dijans"
      )
    end

    # Send a 6-digit code to a citizen's PROPOSED new email so they can
    # confirm ownership before we swap their account email. Sent to the
    # NEW address — the controller verifies the code on a follow-up POST.
    def email_change_verification
      @user      = params[:user]
      @new_email = params[:new_email]
      @code      = params[:code]
      @email_product = "bonid"

      mail(
        to: @new_email,
        subject: "BonID: Konfime nouvo imel ou"
      )
    end

    # Alert emergency contact about incident involving their contact
    def emergency_contact_incident_alert
      @contact = params[:contact]  # EmergencyContact record
      @user    = params[:user]     # The citizen involved in the incident
      @report  = params[:report]   # IncidentReport record
      @role    = params[:role]     # "victim" or "witness"
      @email_product = "bonid"

      mail(
        to: @contact.email,
        subject: "BonID: Alèt Dijans — #{@user.first_name} enplike nan yon ensidan"
      )
    end
  end
end
