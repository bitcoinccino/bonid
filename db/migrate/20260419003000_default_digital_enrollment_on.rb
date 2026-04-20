# frozen_string_literal: true

# BonVote's registration model: BonID IS the registration system. A citizen
# registers online via BonID (primary path) or in person at a BonID-equipped
# location (clerk-assisted). The prior default of `false` treated digital as
# gated-off scaffolding and forced every citizen through a paper-upload
# companion flow — that framing is wrong. Digital registration is the default.
#
# - Flip the column default to `true` so every new election opts into
#   self-service digital enrollment out of the box.
# - Backfill existing rows to `true` so current elections behave the same way.
class DefaultDigitalEnrollmentOn < ActiveRecord::Migration[8.0]
  def up
    change_column_default :bonvote_elections, :allows_digital_enrollment, from: false, to: true
    execute "UPDATE bonvote_elections SET allows_digital_enrollment = TRUE"
  end

  def down
    change_column_default :bonvote_elections, :allows_digital_enrollment, from: true, to: false
  end
end
