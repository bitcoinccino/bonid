class RemoveNotNullFromPartnerPlanIdOnPartnerPayments < ActiveRecord::Migration[8.0]
  def change
    change_column_null :partner_payments, :partner_plan_id, true
  end
end
