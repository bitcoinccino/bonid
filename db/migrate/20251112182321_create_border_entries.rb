# db/migrate/[timestamp]_create_border_entries.rb
class CreateBorderEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :border_entries do |t|
      # --- Associations ---
      t.references :officer, null: false, foreign_key: true
      t.references :visitor_submission, null: false, foreign_key: true
      t.references :partner, foreign_key: true

      # --- Entry / Exit Context ---
      t.string  :port_of_entry, null: false            # e.g. PAP, CAP, OUA
      t.integer :entry_mode, default: 0, null: false   # enum { air, sea, land }
      t.string  :unit_code                            # auto-filled from OfficerConstants::ENTRY_MODE_UNITS

      # --- Entry / Exit Lifecycle ---
      t.datetime :entered_at, null: false
      t.datetime :exited_at
      t.string :transport_reference                   # e.g., flight, vessel, or bus number
      t.string :transport_provider                    # e.g., Delta Air Lines, Carnival Cruise
      t.jsonb  :metadata, default: {}                 # optional geo, IP, device info

      # --- Audit ---
      t.string :officer_badge_id                      # redundancy for auditing
      t.string :officer_unit_name                     # redundancy for reporting
      t.timestamps
    end

    add_index :border_entries, :entry_mode
    add_index :border_entries, :unit_code
    add_index :border_entries, :entered_at
    add_index :border_entries, :exited_at
  end
end
