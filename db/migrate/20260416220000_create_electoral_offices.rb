# frozen_string_literal: true

# Electoral offices are CEP's own field infrastructure:
#
#   - BED (Bureau Électoral Départemental): one per department (two in Ouest
#     and Grande-Anse per CEP's public structure).
#   - BEK (Bureau Électoral Communal):      one per commune.
#
# These are distinct from `PollingCenter` (the election-day voting venues,
# Sant Vòt), and distinct from `Partner` (third-party institutions like banks
# or consulates). An electoral office is permanent CEP infrastructure that
# spans electoral cycles, while polling centers are scoped per-election.
#
# Purpose in BonID:
#   1. Citizen-facing locator — "where can I go for walk-in help or to drop
#      off documents if I can't register online?"
#   2. Audit anchor on `VoterEligibilityRecord.registered_by_electoral_office_id`
#      when a CEP clerk registers a walk-in on the citizen's behalf.
#
# Address reuses the polymorphic `Address` model (see app/models/address.rb),
# which already handles the Haitian hierarchy (Department → Arrondissement →
# Commune → Communal Section) plus postal codes and geocoding.
class CreateElectoralOffices < ActiveRecord::Migration[8.0]
  def change
    create_table :electoral_offices do |t|
      t.string  :name,        null: false
      t.string  :office_type, null: false              # "bed" | "bek"
      t.string  :status,      null: false, default: "planned" # planned | open | closed

      # Geographic scope:
      #   - BED → department_id required, commune_id nil
      #   - BEK → commune_id required (department_id derived via commune)
      t.references :department, foreign_key: true
      t.references :commune,    foreign_key: true

      # Contact + operational metadata
      t.string :phone
      t.string :hours_note       # free-text e.g. "Lendi-Vandredi, 8am-4pm"
      t.integer :priority, null: false, default: 0  # tie-breaker for locator

      t.text :notes

      t.timestamps
    end

    add_index :electoral_offices, :office_type
    add_index :electoral_offices, :status
    # Uniqueness:
    #   - Only one BED per (department) — Ouest/Grande-Anse edge case handled
    #     via `priority` or a second row keyed under the same department.
    #     (Soft guard only — CEP admins add both offices manually.)
    #   - Only one BEK per (commune).
    add_index :electoral_offices,
              [:office_type, :department_id, :commune_id],
              name: "idx_electoral_offices_type_scope"
  end
end
