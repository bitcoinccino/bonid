# frozen_string_literal: true

# OverrideReasons
# ================
# Constants for security override justifications.
# Used when a reviewer/admin approves a submission
# despite active fraud flags (Face 1:N match, Face 1:1 mismatch).
#
module OverrideReasons
  REASONS = {
    "false_positive_twins"   => "Fo pozitif — jimo oswa fanmi pwòch",
    "false_positive_quality" => "Fo pozitif — kalite foto ba",
    "verified_in_person"     => "Verifye an pèsòn — dokiman fizik konfime",
    "reissue_legitimate"     => "Renouvèlman lejitim — menm moun, nouvo dokiman",
    "different_person"       => "Moun diferan — sistèm fè erè nan rekonesans",
    "other"                  => "Lòt (esplike anba a)"
  }.freeze

  def self.options_for_select
    REASONS.map { |key, label| [ label, key ] }
  end

  def self.valid?(reason)
    REASONS.key?(reason.to_s)
  end

  def self.label_for(reason)
    REASONS[reason.to_s] || reason.to_s.humanize
  end
end
