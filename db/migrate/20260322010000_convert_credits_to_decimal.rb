# frozen_string_literal: true

# Migrates the credit system from integer-based (1 credit = $0.01 USD)
# to decimal-based (1 credit = $1.00 USD).
#
# All existing integer values are divided by 100 to produce the correct
# dollar-equivalent decimal. Example: 7704 credits → 77.04 credits ($77.04).
#
# Safety:
#   - Runs inside a transaction (implicit in Rails migrations)
#   - Verifies each partner's balance matches their latest ledger entry
#   - Fully reversible: `down` multiplies by 100 and converts back to integer
#
class ConvertCreditsToDecimal < ActiveRecord::Migration[8.0]
  def up
    # ── Step 1: Convert column types to decimal(10,2) ──
    change_column :partners, :credit_balance, :decimal, precision: 10, scale: 2, default: 0, null: false
    change_column :credit_ledger_entries, :amount, :decimal, precision: 10, scale: 2, null: false
    change_column :credit_ledger_entries, :balance_after, :decimal, precision: 10, scale: 2, null: false
    change_column :partner_payments, :credits, :decimal, precision: 10, scale: 2

    # ── Step 2: Divide all existing values by 100 ──
    execute "UPDATE partners SET credit_balance = credit_balance / 100.0 WHERE credit_balance != 0"
    execute "UPDATE credit_ledger_entries SET amount = amount / 100.0, balance_after = balance_after / 100.0"
    execute "UPDATE partner_payments SET credits = credits / 100.0 WHERE credits IS NOT NULL AND credits != 0"

    # ── Step 3: Verify integrity ──
    # Each partner's credit_balance should match the balance_after of their
    # most recent credit_ledger_entry (if they have any entries).
    mismatches = execute(<<~SQL).to_a
      SELECT p.id, p.credit_balance, latest.balance_after
      FROM partners p
      INNER JOIN (
        SELECT DISTINCT ON (partner_id)
          partner_id, balance_after
        FROM credit_ledger_entries
        ORDER BY partner_id, created_at DESC
      ) latest ON latest.partner_id = p.id
      WHERE ROUND(p.credit_balance::numeric, 2) != ROUND(latest.balance_after::numeric, 2)
    SQL

    if mismatches.any?
      details = mismatches.map { |r| "Partner ##{r['id']}: balance=#{r['credit_balance']} vs ledger=#{r['balance_after']}" }.join(", ")
      raise ActiveRecord::IrreversibleMigration,
        "Credit balance verification FAILED after decimal conversion. Mismatches: #{details}"
    end

    say "✅ Credit decimal migration verified — all partner balances match ledger entries"
  end

  def down
    # ── Reverse: multiply by 100 and convert back to integer ──
    execute "UPDATE partners SET credit_balance = credit_balance * 100 WHERE credit_balance != 0"
    execute "UPDATE credit_ledger_entries SET amount = amount * 100, balance_after = balance_after * 100"
    execute "UPDATE partner_payments SET credits = credits * 100 WHERE credits IS NOT NULL AND credits != 0"

    change_column :partners, :credit_balance, :integer, default: 0, null: false
    change_column :credit_ledger_entries, :amount, :integer, null: false
    change_column :credit_ledger_entries, :balance_after, :integer, null: false
    change_column :partner_payments, :credits, :integer
  end
end
