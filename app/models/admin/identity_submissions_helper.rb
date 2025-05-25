module Admin::IdentitySubmissionsHelper



  def rejection_reason_options
    [
      "Missing CIN or Passport document",
      "CIN or Passport photo is blurry or unreadable",
      "CIN or Passport does not match selfie",
      "Selfie is missing",
      "Selfie is too blurry or unclear",
      "Proof of Address is missing",
      "Proof of Address is invalid (not a Digicel bill)",
      "Proof of Address is outdated",
      "Information provided is inconsistent",
      "Name mismatch between documents",
      "Expired identification document",
      "Low quality or incomplete document uploads",
      "Multiple submissions with conflicting information",
      "Identity could not be verified",
      "Suspicious or altered documents detected",
      "Document tampering suspected",
      "Duplicate identity submission detected",
      "Non-Haitian ID submitted",
      "Incomplete submission",
      "Other (please specify below)"
    ]
  end
end
