# db/migrate/20260208300002_create_incident_analytics_and_linking.rb
class CreateIncidentAnalyticsAndLinking < ActiveRecord::Migration[8.0]
  def change
    # === Case Linking ===
    create_table :incident_links do |t|
      t.references :incident_report, null: false, foreign_key: true
      t.references :linked_incident, null: false, foreign_key: { to_table: :incident_reports }
      t.string :link_type, null: false  # "related", "escalation", "follow_up", "duplicate", "same_suspect"
      t.text :notes
      t.references :created_by, polymorphic: true  # Officer or Admin

      t.timestamps
    end
    add_index :incident_links, [:incident_report_id, :linked_incident_id], unique: true, name: "idx_incident_links_unique"
    add_index :incident_links, :link_type

    # === Enhanced Review Workflow ===
    create_table :incident_reviews do |t|
      t.references :incident_report, null: false, foreign_key: true
      t.references :reviewer, null: false, foreign_key: { to_table: :admin_users }
      t.references :assigned_by, foreign_key: { to_table: :admin_users }
      t.integer :decision  # enum: pending, approved, rejected, escalated, info_requested
      t.text :summary
      t.datetime :assigned_at
      t.datetime :deadline_at
      t.datetime :completed_at
      t.integer :priority, default: 0  # 0=normal, 1=high, 2=urgent

      t.timestamps
    end
    add_index :incident_reviews, [:incident_report_id, :created_at]
    add_index :incident_reviews, [:reviewer_id, :decision]
    add_index :incident_reviews, :priority

    # === Review Comments (Granular Feedback) ===
    create_table :review_comments do |t|
      t.references :incident_review, null: false, foreign_key: true
      t.references :person_involvement, foreign_key: true, null: true  # Optional: specific person
      t.references :admin_user, null: false, foreign_key: true
      t.text :content, null: false
      t.string :comment_type  # "info_request", "correction", "note", "approval_reason"

      t.timestamps
    end

    # === Geographic Hotspots (Aggregated Stats) ===
    create_table :crime_hotspots do |t|
      t.references :commune, null: false, foreign_key: true
      t.references :crime_category, foreign_key: true, null: true  # null = all crimes
      t.date :period_start, null: false
      t.date :period_end, null: false
      t.integer :incident_count, default: 0
      t.float :severity_score, default: 0  # Weighted by crime severity
      t.float :trend_percentage  # Change from previous period
      t.jsonb :breakdown, default: {}  # { "homicide": 5, "theft": 20, ... }

      t.timestamps
    end
    add_index :crime_hotspots, [:commune_id, :period_start, :period_end], name: "idx_hotspots_commune_period"
    add_index :crime_hotspots, :severity_score

    # === Officer Performance Metrics ===
    create_table :officer_metrics do |t|
      t.references :officer, null: false, foreign_key: true
      t.date :period_start, null: false
      t.date :period_end, null: false
      t.integer :reports_submitted, default: 0
      t.integer :reports_approved, default: 0
      t.integer :reports_rejected, default: 0
      t.float :approval_rate, default: 0
      t.float :avg_review_time_hours  # Average time from submit to review
      t.integer :bonid_scans, default: 0
      t.jsonb :crime_type_breakdown, default: {}

      t.timestamps
    end
    add_index :officer_metrics, [:officer_id, :period_start], unique: true

    # === Suspect Alerts (Watch List) ===
    create_table :suspect_alerts do |t|
      t.references :user, foreign_key: true, null: true  # BonID user if known
      t.string :bonid  # If user not in system
      t.string :name  # For non-BonID suspects
      t.string :alert_type, null: false  # "wanted", "armed_dangerous", "missing", "person_of_interest"
      t.integer :priority, default: 0  # 0=low, 1=medium, 2=high, 3=critical
      t.text :description
      t.jsonb :physical_description, default: {}
      t.references :created_by, polymorphic: true
      t.references :source_incident, foreign_key: { to_table: :incident_reports }
      t.datetime :expires_at
      t.boolean :active, default: true

      t.timestamps
    end
    add_index :suspect_alerts, :bonid
    add_index :suspect_alerts, :alert_type
    add_index :suspect_alerts, [:active, :priority]
  end
end
