class AddOtherUseCaseToPartners < ActiveRecord::Migration[8.0]
  def change
    add_column :partners, :other_use_case, :string
  end
end
