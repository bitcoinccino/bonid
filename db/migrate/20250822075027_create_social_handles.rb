class CreateSocialHandles < ActiveRecord::Migration[8.0]
  def change
    create_table :social_handles do |t|
      t.references :user, null: false, foreign_key: true
      t.string :platform, default: "general"
      t.string :handle
      t.boolean :active
      t.date :since
      t.date :until

      t.timestamps
    end
  end
end
