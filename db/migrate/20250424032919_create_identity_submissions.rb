class CreateIdentitySubmissions < ActiveRecord::Migration[8.0]
  def change
    create_table :identity_submissions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :status

      t.timestamps
    end
  end
end
