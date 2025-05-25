class AddWebsiteToPartners < ActiveRecord::Migration[8.0]
  def change
    add_column :partners, :website, :string
  end
end
