class ChangeVerifiedPartnerDefaultInBanks < ActiveRecord::Migration[7.1]
  def change
    change_column_default :banks, :verified_partner, from: nil, to: false
    change_column_null :banks, :verified_partner, false, false
  end
end
