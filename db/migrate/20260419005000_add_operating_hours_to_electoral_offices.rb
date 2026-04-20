# frozen_string_literal: true

# Replaces the free-text `hours_note` with a structured per-day open/close
# schedule. Admins now pick day-by-day in the BED/BEK form rather than
# typing prose. Shape:
#
#   {
#     "mon" => { "open" => "08:00", "close" => "16:00" },
#     "tue" => { "open" => "08:00", "close" => "16:00" },
#     ...
#   }
#
# Days that are closed are simply omitted from the hash. `hours_note` is
# kept on the table (nullable) so any legacy rows aren't lost; nothing
# writes to it anymore.
class AddOperatingHoursToElectoralOffices < ActiveRecord::Migration[8.0]
  def change
    add_column :electoral_offices, :operating_hours, :jsonb, default: {}, null: false
    add_index  :electoral_offices, :operating_hours, using: :gin
  end
end
