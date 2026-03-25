class UpdateQrScansTable < ActiveRecord::Migration[7.0]
  def change
    # Add officer_id column
    add_reference :qr_scans, :officer, foreign_key: true, null: true

    # Add partner_slug column
    add_column :qr_scans, :partner_slug, :string

    # Relax partner_id null constraint
    change_column_null :qr_scans, :partner_id, true
  end
end