# frozen_string_literal: true

class AddOauthToPartners < ActiveRecord::Migration[7.0]
  def up
    # Add OAuth security columns
    add_column :partners, :redirect_uris, :jsonb, default: [], null: false
    add_column :partners, :default_redirect_uri, :string
    add_column :partners, :allowed_scopes, :jsonb, default: [], null: false
    
    # Add indexes for performance
    add_index :partners, :redirect_uris, using: :gin
    add_index :partners, :allowed_scopes, using: :gin
    
    # Backfill existing partners
    reversible do |dir|
      dir.up do
        backfill_existing_partners
      end
    end
  end

  def down
    remove_index :partners, :allowed_scopes if index_exists?(:partners, :allowed_scopes)
    remove_index :partners, :redirect_uris if index_exists?(:partners, :redirect_uris)
    
    remove_column :partners, :allowed_scopes
    remove_column :partners, :default_redirect_uri
    remove_column :partners, :redirect_uris
  end

  private

  def backfill_existing_partners
    valid_scopes = %w[openid profile email phone address]
    
    say "Backfilling OAuth data for existing partners..."
    
    Partner.find_each do |partner|
      # Build a sensible default redirect URI
      default_uri = if partner.respond_to?(:website) && partner.website.present?
                      normalize_url(partner.website) + "/auth/bonid/callback"
                    else
                      "https://#{partner.slug}.example.com/auth/bonid/callback"
                    end
      
      partner.update_columns(
        redirect_uris: [default_uri],
        default_redirect_uri: default_uri,
        allowed_scopes: valid_scopes
      )
      
      say "  ✓ #{partner.name}", true
    end
    
    say "Done! ⚠️  Review and update redirect URIs in admin panel.", true
  end

  def normalize_url(url)
    url = url.strip
    url = "https://#{url}" unless url.start_with?('http://', 'https://')
    url.chomp('/')
  end
end
