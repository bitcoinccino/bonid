# frozen_string_literal: true

# Central feature-flag table. Environment variables are the source of truth
# so we can flip things per-environment without code changes.
#
# Usage:
#   Features.bonvote_tally?  # => false by default
#
# Flags are listed explicitly rather than dynamic method_missing so that
# greps for a flag name surface every reference.
module Features
  module_function

  # BonVote tally / ceremony / multi-sig stack.
  #
  # Shelved 2026-04-20 per project_bonid_cep_sovereignty_line memory:
  # BonID's role for CEP is verification-only. Ballot encryption + tally
  # decryption require CEP to delegate ballot sovereignty to BonID, which
  # is not on the table. The code stays in the tree for a future pilot;
  # this flag keeps it inert until then.
  #
  # Covers:
  #   - PartnerPortal::ElectionDashboardController (tablo / multi_sig / results)
  #   - PartnerPortal::CeremonyController (Shamir shard generation + submit)
  #   - Sidebar links for the three above
  def bonvote_tally?
    ENV["FEATURE_BONVOTE_TALLY"].to_s.downcase == "true"
  end
end
