# frozen_string_literal: true

module Citizens
  class QrScanMailer < Citizens::BaseMailer
    default from: "bonid@verifyem.ht"

    # scan_log is a QrScanLog record (AUDIT source of truth)
    def scan_alert(scan_log)
      @scan_log   = scan_log
      @submission = scan_log.identity_submission
      @user       = @submission.user
      @partner    = scan_log.partner
      @officer    = scan_log.officer

      with_citizen_locale(@user) do
        date = I18n.l(scan_log.scanned_at, format: t("mailers.qr_scan.date_format"))
        mail(to: @user.email, subject: t("mailers.qr_scan.subject", date: date))
      end
    end
  end
end
