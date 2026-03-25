class AddBankingAgentIdToQrScans < ActiveRecord::Migration[8.0]
  def change
    add_reference :qr_scans, :banking_agent, foreign_key: { to_table: :users }, index: true
  end
end
