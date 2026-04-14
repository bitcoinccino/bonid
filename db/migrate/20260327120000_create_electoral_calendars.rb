# frozen_string_literal: true

class CreateElectoralCalendars < ActiveRecord::Migration[8.0]
  def change
    create_table :electoral_calendars do |t|
      t.references :bonvote_election, null: false, foreign_key: { on_delete: :cascade }
      t.string     :phase,            null: false
      t.string     :name,             null: false
      t.date       :start_date,       null: false
      t.date       :end_date,         null: false
      t.text       :description
      t.string     :responsible_body
      t.boolean    :public_visible,   default: true, null: false

      t.timestamps
    end

    add_index :electoral_calendars, [:bonvote_election_id, :phase]
    add_index :electoral_calendars, [:start_date, :end_date]
    add_index :electoral_calendars, :phase
  end
end
