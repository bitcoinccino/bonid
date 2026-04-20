# frozen_string_literal: true

# Companion (paper) flow: a citizen who registers in person at a CEP BED/BEK
# walks out with a paper receipt. They can later photograph that receipt in
# BonID; we OCR it and stamp the slip onto their VoterEligibilityRecord so
# the paper artifact becomes un-losable.
#
# Columns:
#   - paper_receipt_number    : the receipt # printed by the CEP office
#   - paper_receipt_issued_at : when the CEP office issued the slip (from OCR
#                               or manual entry)
#   - paper_receipt_verified_at : when BonID confirmed the upload (server time)
#
# The actual photo is stored via ActiveStorage (`has_one_attached
# :paper_receipt_image`) — no DB column needed.
class AddPaperReceiptFieldsToVoterEligibilityRecords < ActiveRecord::Migration[8.0]
  def change
    change_table :voter_eligibility_records do |t|
      t.string   :paper_receipt_number
      t.datetime :paper_receipt_issued_at
      t.datetime :paper_receipt_verified_at
    end

    add_index :voter_eligibility_records,
              [ :bonvote_election_id, :paper_receipt_number ],
              where: "paper_receipt_number IS NOT NULL",
              name: "idx_voter_records_on_election_and_paper_receipt"
  end
end
