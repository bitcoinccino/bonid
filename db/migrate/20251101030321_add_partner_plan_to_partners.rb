class AddPartnerPlanToPartners < ActiveRecord::Migration[8.0]
  def change
    add_reference :partners, :partner_plan, null: true, index: true, foreign_key: true
  end
end
