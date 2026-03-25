class CreateOfficerComplaints < ActiveRecord::Migration[7.2]
  def change
    create_table :officer_complaints do |t|
      # === Pillar 6: Tracking & Status ===
      t.string  :tracking_number,    null: false, index: { unique: true }
      t.string  :status,             null: false, default: "submitted"
      t.string  :uuid,               null: false, index: { unique: true }

      # === Pillar 1: Complainant Identity ===
      t.string  :complainant_type,   null: false, default: "citizen"
      t.string  :complainant_role,   null: false
      t.string  :complainant_name                  # Pre-filled from BonID/BonTouris
      t.string  :complainant_bonid                 # user.bonid OR visitor.bonid
      t.string  :complainant_cin                   # user.id_number (CIN / passport)
      t.string  :complainant_phone
      t.string  :complainant_email
      t.string  :complainant_nationality            # Relevant for tourists

      # FK to authenticated session (nullable for anonymous)
      t.references :user,               null: true, foreign_key: true
      t.bigint  :visitor_submission_id             # FK to visitor_submissions (no Rails FK for bigint mismatch safety)
      t.index   :visitor_submission_id

      # === Pillar 2: Incident Details ===
      t.datetime :occurred_at,          null: false
      t.text    :location_description   # Free-text: street, commissariat name
      t.string  :pnh_unit_involved      # e.g., "BOID", "CIMO", "UTAG"
      t.string  :routed_directorate     # e.g., "DDO" — auto-set for IGPNH routing

      # Geo hierarchy of incident (not complainant's home address)
      t.references :department,         null: true, foreign_key: true
      t.references :commune,            null: true, foreign_key: true
      t.references :communal_section,   null: true, foreign_key: true

      # === Pillar 3: Accused Officer Identification ===
      # All nullable — citizen may only have physical description
      t.bigint  :accused_officer_id               # FK to officers if badge matched
      t.index   :accused_officer_id
      t.string  :accused_officer_badge             # Badge ID if citizen knows it
      t.string  :accused_officer_name              # Name if citizen knows it
      t.string  :accused_officer_vehicle           # Patrol car number e.g. "PNH-1234"
      t.string  :accused_officer_unit              # Unit if known e.g. "CIMO"
      t.text    :physical_description              # Rank visible, clothing, features

      # === Pillar 4: Allegations ===
      t.string  :allegation_category,  null: false  # "Corruption", "Abus de pouvoir"
      t.string  :specific_allegation,  null: false  # "Racket / Pot-de-vin"

      # === Pillar 5: Evidence & Narrative ===
      t.text    :narrative,             null: false  # Legal statement of facts (min 50 chars)
      t.jsonb   :witnesses,             null: false, default: []
      # Evidence files attached via ActiveStorage (has_many_attached :evidences)

      # === Pillar 6: Workflow / IGPNH Internal ===
      t.bigint  :assigned_to_id                    # IGPNH investigator (Officer)
      t.index   :assigned_to_id
      t.bigint  :assigned_by_id                    # Admin who assigned
      t.text    :internal_notes                    # IGPNH internal case notes
      t.text    :resolution_notes                  # Final outcome notes

      # Workflow timestamps
      t.datetime :submitted_at
      t.datetime :reviewed_at
      t.datetime :investigation_opened_at
      t.datetime :resolved_at

      t.timestamps
    end

    add_index :officer_complaints, :status
    add_index :officer_complaints, :routed_directorate
    add_index :officer_complaints, :allegation_category
    add_index :officer_complaints, :occurred_at
    add_index :officer_complaints, :complainant_bonid
    add_index :officer_complaints, :complainant_type
  end
end
