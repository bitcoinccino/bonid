# app/controllers/concerns/scannable_verification.rb
module ScannableVerification
  extend ActiveSupport::Concern

  included do
    private

    def handle_verification!(token:, partner_slug:, source:)
      submission = IdentitySubmission.approved.find_by(verification_token: token)
      return [ nil, redirect_to(root_path, alert: "Invalid or expired BonID.") ] unless submission

      if submission.expires_at&.past?
        return [ nil, redirect_to(root_path, alert: "This BonID has expired.") ]
      end

      partner = Partner.find_by(slug: partner_slug)

      unless recently_scanned?(submission)
        QrScanLogger.log!(
          submission: submission,
          request: request,
          source: source,
          partner: partner
        )
      end

      [ submission, partner ]
    end

    def recently_scanned?(submission)
      last_scan = submission.qr_scan_logs.order(created_at: :desc).first
      last_scan && last_scan.created_at > 30.seconds.ago
    end
  end
end
