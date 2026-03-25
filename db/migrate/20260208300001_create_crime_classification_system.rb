# db/migrate/20260208300001_create_crime_classification_system.rb
class CreateCrimeClassificationSystem < ActiveRecord::Migration[8.0]
  def change
    # === Crime Categories (Top Level) ===
    create_table :crime_categories do |t|
      t.string :name, null: false
      t.string :code, null: false, limit: 10  # e.g., "VIOLENT", "PROPERTY"
      t.text :description
      t.integer :display_order, default: 0
      t.boolean :active, default: true

      t.timestamps
    end
    add_index :crime_categories, :code, unique: true
    add_index :crime_categories, :active

    # === Crime Types (Hierarchical) ===
    create_table :crime_types do |t|
      t.references :crime_category, null: false, foreign_key: true
      t.string :name, null: false
      t.string :code, null: false, limit: 10  # e.g., "HOMO", "SEXV"
      t.text :description
      t.text :legal_reference  # Legal code references
      t.integer :base_severity, default: 1  # 1-5 scale
      t.integer :display_order, default: 0
      t.boolean :requires_victim, default: true
      t.boolean :requires_witness, default: false
      t.boolean :requires_location, default: true
      t.boolean :active, default: true
      t.jsonb :metadata, default: {}  # Flexible additional data

      t.timestamps
    end
    add_index :crime_types, :code, unique: true
    add_index :crime_types, :base_severity
    add_index :crime_types, :active
    add_index :crime_types, [:crime_category_id, :active]

    # === Severity Rules (Context-Dependent) ===
    create_table :severity_rules do |t|
      t.references :crime_type, null: false, foreign_key: true
      t.string :condition_type  # e.g., "victim_count", "weapon_involved", "minor_involved"
      t.jsonb :condition_value  # e.g., {"min": 2} or {"weapon_types": ["firearm", "knife"]}
      t.integer :severity_modifier  # +1, +2, etc.
      t.text :description

      t.timestamps
    end
    add_index :severity_rules, [:crime_type_id, :condition_type]

    # === Related Crimes (For Case Linking Suggestions) ===
    create_table :related_crime_types do |t|
      t.references :crime_type, null: false, foreign_key: true
      t.references :related_crime_type, null: false, foreign_key: { to_table: :crime_types }
      t.string :relationship_type  # "often_together", "escalation", "subset"
      t.float :correlation_score, default: 0.5  # 0-1 how often they appear together

      t.timestamps
    end
    add_index :related_crime_types, [:crime_type_id, :related_crime_type_id], unique: true, name: "idx_related_crimes_unique"

    # === Update IncidentReport to reference CrimeType ===
    add_reference :incident_reports, :crime_type_record, foreign_key: { to_table: :crime_types }, null: true
    # Keep legacy crime_type string for migration period
  end
end
