# frozen_string_literal: true

# Adds per-partner ownership to polling centers so URL-tampered access
# (a partner_admin guessing /:id) can no longer cross-edit centers
# created by other partner organisations.
#
# CEP (sector="cep") retains global write access by policy in the
# controller — the column lets us scope all *other* partners (consulates,
# ministries, NGOs) to centers they created themselves.
#
# Backfill assigns every existing center to the CEP partner since CEP
# is the only entity that has been managing them in v1.
class AddPartnerOwnershipToPollingCenters < ActiveRecord::Migration[8.0]
  def up
    change_table :polling_centers, bulk: true do |t|
      t.references :partner, foreign_key: true, null: true
      # PartnerAdmin is STI on the `users` table, so the FK targets :users.
      t.references :created_by_partner_admin,
                   foreign_key: { to_table: :users },
                   null: true
    end

    cep = Partner.find_by(sector: "cep")
    if cep
      execute <<~SQL.squish
        UPDATE polling_centers
        SET partner_id = #{cep.id}
        WHERE partner_id IS NULL
      SQL
    end

    # Lock the column down once backfilled. New rows must always carry an
    # owning partner — the controller sets this from current_partner.
    if PollingCenter.where(partner_id: nil).none?
      change_column_null :polling_centers, :partner_id, false
    end
  end

  def down
    change_table :polling_centers, bulk: true do |t|
      t.remove_references :created_by_partner_admin, foreign_key: { to_table: :users }
      t.remove_references :partner, foreign_key: true
    end
  end
end
