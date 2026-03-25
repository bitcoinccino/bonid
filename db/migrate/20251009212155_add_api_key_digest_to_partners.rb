# db/migrate/20251022174500_add_api_key_digest_to_partners.rb
class AddApiKeyDigestToPartners < ActiveRecord::Migration[8.0]
  def change
    add_column :partners, :api_key_digest, :string
    add_index  :partners, :api_key_digest, unique: true

    add_column :partners, :active, :boolean, default: true, null: false
  end
end
