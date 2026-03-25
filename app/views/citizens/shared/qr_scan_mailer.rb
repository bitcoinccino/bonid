# app/mailers/citizens/qr_scan_mailer.rb
class Citizens::QrScanMailer < ApplicationMailer
  default from: "bonid@verifyem.ht"

  def scan_alert(scan)
    @scan     = scan
    @user     = scan.identity_submission.user
    @partner  = scan.partner
    @officer  = scan.officer

    mail(
      to: @user.email,
      subject: "🔔 Your BonID was scanned on #{scan.scanned_at.strftime("%b %d, %Y")}"
    )
  end
end
