# frozen_string_literal: true

# ==========================================================================
# BonGouvHelper — View helpers for BonGouv verification pages.
# ==========================================================================
module BongouvHelper
  # Mask citizen name for public verification page.
  # "Diaphnie Casimir" → "D*** C***"
  def mask_name(first_name, last_name)
    masked_first = first_name.present? ? "#{first_name[0]}#{'*' * [first_name.length - 1, 3].min}" : "***"
    masked_last  = last_name.present?  ? "#{last_name[0]}#{'*' * [last_name.length - 1, 3].min}"  : "***"
    "#{masked_first} #{masked_last}"
  end

  # Heavier masking for public page — only last 4.
  # "DC-1990-F-OUEST-P4521089" → "MB••••••••••1089"
  def mask_bonid_public(bonid)
    return "—" if bonid.blank?
    stripped = bonid.gsub("-", "")
    last4 = stripped.last(4)
    dots = "•" * [stripped.length - 6, 8].max
    "MB#{dots}#{last4}"
  end
end
