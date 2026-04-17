# frozen_string_literal: true

# Phase 3: BonID pivots to digital-first registration. A citizen self-enrolls
# online (default path) and receives a BonID-generated receipt they can print
# or save. A CEP clerk can still register walk-ins at a BED/BEK — same result,
# same receipt.
#
# Schema changes:
#
#   - `source` distinguishes the origin of the record:
#       "digital" = citizen self-registered online (primary)
#       "clerk"   = CEP staff registered them at a BED/BEK
#       "hybrid"  = future: citizen pre-checked online, clerk confirmed
#
#   - `registered_by_electoral_office` is the audit FK for clerk-assisted
#     registrations at a specific BED/BEK. (Existing `registered_by_partner`
#     stays for consulate / third-party registration channels.)
#
#   - `cep_signature` / `cep_signed_at` hold an Ed25519 signature over the
#     receipt payload. This turns the BonID receipt into something a
#     CEP-issued tablet at a polling station could verify offline. No-op
#     until `Election::CepSigningService` is configured with keys.
#
#   - `allows_digital_enrollment` on bonvote_elections is the CEP policy
#     knob that lets CEP flip the flow off if needed (e.g. pending decree
#     amendment). Defaults to false for safety — the active election must
#     explicitly opt in.
class ExtendVoterRecordsDigitalFirst < ActiveRecord::Migration[8.0]
  def change
    change_table :voter_eligibility_records do |t|
      t.string   :source, null: false, default: "digital"
      t.references :registered_by_electoral_office,
                   foreign_key: { to_table: :electoral_offices }
      t.text     :cep_signature
      t.datetime :cep_signed_at
      t.datetime :receipt_generated_at
    end

    # Backfill: existing rows were created under the old "digital-only" code
    # path, so default "digital" is correct. No explicit update needed.

    add_column :bonvote_elections,
               :allows_digital_enrollment,
               :boolean,
               default: false,
               null: false
  end
end
