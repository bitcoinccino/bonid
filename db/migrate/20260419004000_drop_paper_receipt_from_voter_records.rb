# frozen_string_literal: true

# Removes the paper-receipt companion columns and attachment. BonID IS the
# voter-registration system (online self-service + clerk-assisted at BonID-
# equipped desks); the paper-slip import flow is gone, so these columns have
# no writers or readers left in the app.
#
# Dropped:
#   - paper_receipt_number / paper_receipt_issued_at / paper_receipt_verified_at
#   - idx_voter_records_on_election_and_paper_receipt (partial unique index)
#   - paper_receipt_image ActiveStorage attachments (and their blobs when
#     orphaned) for voter_eligibility_records.
class DropPaperReceiptFromVoterRecords < ActiveRecord::Migration[8.0]
  def up
    # Purge ActiveStorage attachments first so blobs can be reclaimed by
    # the purger. Safe even if zero rows exist.
    execute <<~SQL
      DELETE FROM active_storage_attachments
      WHERE record_type = 'VoterEligibilityRecord'
        AND name = 'paper_receipt_image';
    SQL

    if index_exists?(:voter_eligibility_records,
                     [:bonvote_election_id, :paper_receipt_number],
                     name: "idx_voter_records_on_election_and_paper_receipt")
      remove_index :voter_eligibility_records,
                   name: "idx_voter_records_on_election_and_paper_receipt"
    end

    remove_column :voter_eligibility_records, :paper_receipt_number,      :string
    remove_column :voter_eligibility_records, :paper_receipt_issued_at,   :datetime
    remove_column :voter_eligibility_records, :paper_receipt_verified_at, :datetime
  end

  def down
    add_column :voter_eligibility_records, :paper_receipt_number,      :string
    add_column :voter_eligibility_records, :paper_receipt_issued_at,   :datetime
    add_column :voter_eligibility_records, :paper_receipt_verified_at, :datetime

    add_index :voter_eligibility_records,
              [:bonvote_election_id, :paper_receipt_number],
              where: "paper_receipt_number IS NOT NULL",
              name: "idx_voter_records_on_election_and_paper_receipt"
  end
end
