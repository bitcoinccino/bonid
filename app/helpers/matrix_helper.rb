# !-- ================================

#  app/helpers/matrix_helper.rb
# =================================== -->

module MatrixHelper
  def onboarding_steps
    [
      {
        number: 1,
        icon: "ri-upload-cloud-2-line",
        title: "Upload Documents",
        description: "Upload your National ID (CIN), Driver's License or Passport, a selfie, and one supporting document.",
        timing: "Takes under 2 minutes."
      },
      {
        number: 2,
        icon: "ri-fingerprint-line",
        title: "Get Verified",
        description: "Your identity is securely reviewed by BonID staff and verified using advanced AI tools to confirm authenticity.",
        timing: "Verification in under 10 seconds."
      },
      {
        number: 3,
        icon: "ri-qr-scan-2-line",
        title: "Use Anywhere",
        description: "Once verified, use your BonID across Haiti for banking, hospitals, aid programs, voting, and travel — all with one secure QR code.",
        timing: ""
      }
    ]
  end
end
