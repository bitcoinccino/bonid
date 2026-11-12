# frozen_string_literal: true

module Citizens
  class QrScanMailer < Citizens::BaseMailer
    default from: "bonid@verifyem.ht"
    layout "mailer" # shared Haitian-blue email style

    # scan_log is a QrScanLog record (AUDIT source of truth)
    def scan_alert(scan_log)
      @scan_log   = scan_log
      @submission = scan_log.identity_submission
      @user       = @submission.user
      @partner    = scan_log.partner
      @officer    = scan_log.officer

      mail(
        to: @user.email,
        subject: "BonID: Your BonID was checked on #{scan_log.scanned_at.strftime('%b %-d, %Y')}"
      )
    end
  end
end
