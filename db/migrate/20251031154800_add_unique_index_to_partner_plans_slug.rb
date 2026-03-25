class AddUniqueIndexToPartnerPlansSlug < ActiveRecord::Migration[8.0]
  def change
    add_index :partner_plans, :slug, unique: true
  end
end
