class CreateOauthApplications < ActiveRecord::Migration[8.0]
  def change
    create_table :oauth_applications do |t|
      t.string :name
      t.string :uid
      t.string :secret_digest
      t.text :redirect_uri
      t.string :scopes
      t.references :partner, null: false, foreign_key: true

      t.timestamps
    end
  end
end
