# frozen_string_literal: true

class CreateVisitorScanEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :visitor_scan_events do |t|
      t.references :visitor_submission, null: true, foreign_key: true

      # What was checked
      t.string  :bon_touris_id, null: false
      t.string  :input_method,  null: false, default: "qr_payload" # qr_payload | manual

      # Result
      t.boolean :ok,            null: false, default: false
      t.string  :status,        null: false, default: "verification_failed"
      t.string  :message

      # "Who" performed the check (best effort)
      t.string  :actor_kind              # public | partner | officer | admin | api | unknown
      t.string  :actor_label             # e.g. "UNIBANK (Partner)" or "Public"
      t.boolean :actor_verified, default: false

      # Request metadata
      t.string :ip_address
      t.text   :user_agent
      t.string :accept_language
      t.text   :referer
      t.string :request_id

      # Optional "where" (best-effort; nil-safe)
      t.string :country
      t.string :region
      t.string :city

      # Email notification tracking (throttle)
      t.datetime :notified_at

      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :visitor_scan_events, :bon_touris_id
    add_index :visitor_scan_events, %i[visitor_submission_id occurred_at]
    add_index :visitor_scan_events, :notified_at
  end
end
