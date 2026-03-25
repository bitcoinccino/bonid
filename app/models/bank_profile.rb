class BankProfile < ApplicationRecord
  belongs_to :user
  belongs_to :bank, optional: true

  # =========================================================
  # ENUMS — MUST match DB types (your migration uses STRING)
  # =========================================================
  enum :account_source, {
    bank:          "bank",
    mobile_wallet: "mobile_wallet",
    crypto_wallet: "crypto_wallet"
  }, prefix: true

  enum :account_type, {
    checking: "checking",
    savings:  "savings",
    business: "business",
    wallet:   "wallet"
  }, prefix: true

  enum :status, {
    pending:  "pending",
    verified: "verified",
    rejected: "rejected"
  }, prefix: true

  enum :access_level, {
  read_only:  "read_only",
  read_write: "read_write"
}, prefix: true, suffix: true


  CURRENCIES = {
    "HTG"  => "HTG",
    "USD"  => "USD",
    "USDC" => "USDC",
    "BTC"  => "BTC",
    "SOL"  => "SOL",
    "ETH"  => "ETH"
  }.freeze

  BANKS = [
    [ "Unibank", "unibank" ],
    [ "Sogebank", "sogebank" ],
    [ "BUH", "buh" ],
    [ "BNC", "bnc" ],
    [ "Capital Bank", "capital_bank" ],
    [ "Other", "other" ]
  ].freeze

  # Mobile wallet providers popular in Haiti
  MOBILE_WALLET_PROVIDERS = [
    [ "MonCash", "moncash" ],
    [ "NatCash", "natcash" ],
    [ "Zellus", "zellus" ],
    [ "Other", "other" ]
  ].freeze

  # Crypto wallet providers
  CRYPTO_WALLET_PROVIDERS = [
    [ "Coinbase Wallet", "coinbase" ],
    [ "Phantom", "phantom" ],
    [ "MetaMask", "metamask" ],
    [ "Trust Wallet", "trust_wallet" ],
    [ "Ledger", "ledger" ],
    [ "Other", "other" ]
  ].freeze

  # Blockchain networks
  CRYPTO_CHAINS = [
    [ "Solana", "solana" ],
    [ "Ethereum", "ethereum" ],
    [ "Base", "base" ],
    [ "BNB Chain", "bnb" ],
    [ "Polygon", "polygon" ],
    [ "Bitcoin", "bitcoin" ],
    [ "Other", "other" ]
  ].freeze

  # =========================================================
  # VALIDATIONS
  # =========================================================
  validates :user, presence: true
  validates :account_source, presence: true

  # --- Bank account validations ---
  with_options if: :account_source_bank? do
    validates :bank_name, presence: true
    validates :account_number, presence: true
    validates :account_type, presence: true
  end

  # --- Mobile Wallet (MonCash, NatCash, Digicel Wallet) ---
  with_options if: :account_source_mobile_wallet? do
    validates :wallet_provider, presence: true         # ex: MonCash
    validates :wallet_address,  presence: true         # phone number
  end

  # --- Crypto Wallet (Solana, Ethereum, etc.) ---
  with_options if: :account_source_crypto_wallet? do
    validates :wallet_provider, presence: true         # ex: Phantom, MetaMask
    validates :wallet_address,  presence: true         # public wallet address
    validates :chain,           presence: true         # ex: solana, ethereum, base
  end

  # =========================================================
  # CALLBACKS
  # =========================================================
  before_validation :auto_fill_bank_name
  before_validation :set_default_currency

  # =========================================================
  # HELPERS
  # =========================================================
  def kyc_verified?
    kyc_verified
  end

  def bank?
    account_source_bank?
  end

  def mobile_wallet?
    account_source_mobile_wallet?
  end

  def crypto_wallet?
    account_source_crypto_wallet?
  end

  private

  # Auto-fill bank_name from Bank table if present
  def auto_fill_bank_name
    return unless bank.present?
    self.bank_name ||= bank.name
  end

  def set_default_currency
    self.currency ||= "HTG"
  end
end
