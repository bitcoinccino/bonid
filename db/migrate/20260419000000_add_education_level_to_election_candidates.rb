# frozen_string_literal: true

# Adds the education_level column that drives Article 185 fee discounts:
#   - masters   → 30% reduction
#   - doctorate → 50% reduction
# Women are exempt entirely per Article 185, driven off the existing `sex`
# column, so no separate flag is needed for that.
#
# The older `fee_reduced` / `fee_reduction_reason` columns stay in place for
# historical rows; the app stops writing to them.
class AddEducationLevelToElectionCandidates < ActiveRecord::Migration[8.0]
  def change
    add_column :election_candidates, :education_level, :string
  end
end
