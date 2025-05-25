class CreateIncidentReports < ActiveRecord::Migration[8.0]
  def change
    create_table :incident_reports do |t|
      t.references :officer, null: false, foreign_key: true
      t.string :crime_type
      t.text :description
      t.datetime :occurred_at
      t.jsonb :media
      t.references :address, null: false, foreign_key: true

      t.timestamps
    end
  end
end
