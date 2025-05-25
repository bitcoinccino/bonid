class AddAddressableToAddresses < ActiveRecord::Migration[8.0]
  def change
    add_reference :addresses, :addressable, polymorphic: true, null: true # ✅ allow nulls for now
  end
end
