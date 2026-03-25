# frozen_string_literal: true

# app/controllers/concerns/plan_enforceable.rb
#
# Enforces prepaid credit balance on API endpoints.
# Partners buy credits (1 Credit = $0.01 USD ≈ 1.5 HTG) and each API call
# deducts credits based on its tier:
#
#   Standard (49 credits / $0.49):            QR scan, status check
#   Health & Biometric (99 credits / $0.99):  Blood type, allergies, physical profile
#   Civil & Social (129 credits / $1.29):     Family records, emergency contacts, social trust
#   Verification (149 credits / $1.49):       Full identity, consent requests (no liveness)
#   Premium (199 credits / $1.99):            Liveness + face match, crime, crypto KYC
#
# Returns:
#   402 Payment Required — partner has no credits (balance = 0)
#   402 Payment Required — partner has insufficient credits for this call
#
module PlanEnforceable
  extend ActiveSupport::Concern

  included do
    before_action :enforce_credit_balance!, if: -> { @partner.present? }
    after_action  :deduct_credits!, if: -> { @partner.present? && response.successful? }
  end

  private

  # ============================================================
  # CREDIT BALANCE CHECK (before_action)
  # Ensures the partner has enough credits for this API call.
  # ============================================================
  def enforce_credit_balance!
    return if skip_plan_enforcement?

    cost = credit_cost_for_request
    return if cost.zero? # Free endpoints (bonid_lookup, certificates)

    balance = @partner.credit_balance

    if balance <= 0
      return render_plan_error(
        status: :payment_required,
        error: "No credits remaining",
        message: "Balans ou a zewo. Rechaje kont ou pou kontinye itilize API a.",
        credit_balance: 0,
        credit_cost: cost,
        top_up_url: "/partner_portal/billing"
      )
    end

    if balance < cost
      return render_plan_error(
        status: :payment_required,
        error: "Insufficient credits",
        message: "Ou bezwen #{cost} kredi pou operasyon sa a, men ou gen sèlman #{balance}. Rechaje kont ou.",
        credit_balance: balance,
        credit_cost: cost,
        tier: CreditLedgerEntry.tier_for(endpoint_key),
        top_up_url: "/partner_portal/billing"
      )
    end
  end

  # ============================================================
  # CREDIT DEDUCTION (after_action — only on success)
  # Deducts credits atomically and creates ledger entry.
  # ============================================================
  def deduct_credits!
    return if skip_plan_enforcement?

    cost = credit_cost_for_request
    return if cost.zero?

    bonid_param = params[:bonid].to_s.strip.presence

    @partner.deduct_credits!(
      amount: cost,
      endpoint_key: endpoint_key,
      description: deduction_description(cost, bonid_param),
      bonid: bonid_param,
      ip_address: request.remote_ip
    )

    # Set credit headers for partner visibility
    set_credit_response_headers(cost)
  rescue Partner::InsufficientCreditsError
    # Race condition: balance changed between before/after action.
    # Response already sent — log for reconciliation.
    Rails.logger.warn("[Credits] Race condition: #{@partner.slug} had insufficient credits after successful response")
  rescue => e
    Rails.logger.error("[Credits] Deduction failed for #{@partner.slug}: #{e.message}")
  end

  # ============================================================
  # HELPERS
  # ============================================================

  def credit_cost_for_request
    # Pull scopes from consent (if present) or from params
    resolved_scopes = if @consent.present? && @consent.respond_to?(:scopes)
                        @consent.scopes
                      else
                        params[:scopes]
                      end

    resolved_tx_type = if @consent.present? && @consent.respond_to?(:transaction_type)
                         @consent.transaction_type
                       else
                         params[:transaction_type]
                       end

    @_credit_cost ||= CreditLedgerEntry.cost_for(
      endpoint_key,
      transaction_type: resolved_tx_type,
      scopes: resolved_scopes
    )
  end

  def endpoint_key
    @_endpoint_key ||= "#{self.class.name}##{action_name}"
  end

  def deduction_description(cost, bonid)
    tier = CreditLedgerEntry.tier_for(endpoint_key)
    bonid.present? ? "#{tier}: #{bonid}" : tier
  end

  def set_credit_response_headers(cost)
    balance = @partner.credit_balance
    response.set_header("X-BonID-Credits-Used", cost.to_s)
    response.set_header("X-BonID-Credits-Remaining", balance.to_s)
  end

  def skip_plan_enforcement?
    Rails.env.test? || oauth_endpoint?
  end

  def oauth_endpoint?
    request.path.start_with?("/oauth/")
  end

  def render_plan_error(status:, error:, message:, **extras)
    payload = {
      status: status.to_s.gsub("_", " "),
      error: error,
      message: message,
      timestamp: Time.current.iso8601
    }.merge(extras)

    sign_response(payload) if respond_to?(:sign_response, true)
    render json: payload, status: status
  end
end
