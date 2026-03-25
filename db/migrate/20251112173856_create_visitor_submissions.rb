class CreateVisitorSubmissions < ActiveRecord::Migration[8.0]
  def change
    create_table :visitor_submissions do |t|
      # --- Core Identity Info ---
      t.string  :first_name, null: false
      t.string  :last_name, null: false
      t.date    :dob, null: false
      t.string  :sex, null: false
      t.string  :passport_number, null: false
      t.string  :country_code, null: false  # ISO 3166 country code

      # --- Visit Context ---
      t.string  :purpose_of_visit, null: false   # e.g. tourism, business, official
      t.string  :accommodation_address           # optional stay location
      t.integer :stay_duration_days              # optional self-reported duration
      t.integer :entry_mode, default: 0, null: false  # enum: { air: 0, sea: 1, land: 2 }

      # --- Transportation Details ---
      t.string :transport_provider, null: false  # e.g., "Delta Air Lines", "Carnival Cruise", "Hertz Rental", "Gonave Ferry", "Santiago Border Bus"
      t.jsonb :transport_details, default: {}    # Flexible: { flight_number: "DL456", departure_city: "ATL", vehicle_id: "ABC123" }

      # --- BonID Integration ---
      t.string :bonid, index: { unique: true }
      t.datetime :expires_at
      t.references :user, null: false, foreign_key: true
      t.references :identity_submission, foreign_key: true  # links to main BonID record

      # --- Audit + Analytics ---
      t.string :port_of_entry, null: false       # e.g. PAP, Cap-Haïtien, Ouanaminthe
      t.string :transport_reference              # e.g. flight #, vessel, bus name (now optional with transport_details)
      t.jsonb  :metadata, default: {}            # optional geo, device, or form data
      t.timestamps
    end

    add_index :visitor_submissions, :passport_number
    add_index :visitor_submissions, :country_code
    add_index :visitor_submissions, :entry_mode
    # Indexes for transport
    add_index :visitor_submissions, :transport_provider  # Quick queries by airline/bus
    add_index :visitor_submissions, [ :entry_mode, :transport_provider ]  # e.g., air arrivals by Delta
  end
end
