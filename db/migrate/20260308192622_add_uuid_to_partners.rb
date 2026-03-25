# db/migrate/20260308192622_add_uuid_to_partners.rb
#
# Adds a UUID column to partners for Zero-Trust architecture.
# Sequential integer IDs in URLs expose partner count and enable
# IDOR attacks (e.g., unapproved partner at ID 102 guessing ID 101).
#
# After this migration:
#   • Admin routes use param: :uuid
#   • Serializers expose UUID, not integer ID
#   • Internal foreign keys (partner_id) remain integer for performance
#
class AddUuidToPartners < ActiveRecord::Migration[8.0]
  def change
    add_column :partners, :uuid, :uuid, default: -> { "gen_random_uuid()" }, null: false
    add_index  :partners, :uuid, unique: true
  end
end
