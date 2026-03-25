class MakeOfficerIdNullableInFailedBonidLookups < ActiveRecord::Migration[8.0]
  def change
    change_column_null :failed_bonid_lookups, :officer_id, true
  end
end
