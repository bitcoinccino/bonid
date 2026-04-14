# frozen_string_literal: true

class CreatePilotFeedbacks < ActiveRecord::Migration[8.0]
  def change
    create_table :pilot_feedbacks do |t|
      t.string  :election_id,    null: false                # e.g. "2026-test-pilot-1"
      t.string  :receipt_id                                  # links to ballot receipt (anonymous)
      t.string  :ballot_hash                                 # optional, for cross-reference
      t.integer :time_to_vote,    null: false                # 1 = <2min, 2 = 2-5min, 3 = >5min
      t.integer :photo_clarity,   null: false                # 1 = clear, 2 = ok, 3 = difficult
      t.integer :trust_level,     null: false                # 1 = full trust, 2 = need more info, 3 = no trust
      t.text    :comment                                     # optional free text
      t.string  :lang,            default: "ht"              # language used (ht/fr/en)
      t.string  :channel                                     # remote / consulate / kiosk
      t.string  :consulate_id                                # diplomatic mission ID if applicable
      t.string  :ip_country                                  # geolocation for analysis
      t.string  :user_agent                                  # device/browser info
      t.timestamps
    end

    add_index :pilot_feedbacks, :election_id
    add_index :pilot_feedbacks, :receipt_id, unique: true    # one feedback per ballot
    add_index :pilot_feedbacks, :trust_level                 # quick filter for the critical metric
  end
end
