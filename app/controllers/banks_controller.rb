class BanksController < ApplicationController
  before_action :normalize_name, only: [ :swift_lookup ]

  # GET /banks/swift_lookup?name=Unibank%20S.A.
  def swift_lookup
    return render_error(:missing_name) if @name.blank?

    # Try accent-safe lookup with fallback
    bank = Bank.lookup_by_name(@name).first

    if bank
      render json: {
        swift_code: bank.swift_code,
        country: bank.country,
        verified_partner: bank.verified_partner
      }
    else
      render_error(:not_found)
    end
  rescue => e
    Rails.logger.error("💥 [BanksController#swift_lookup] #{e.class}: #{e.message}")
    render_error(:lookup_failed)
  end

  private

  def normalize_name
    @name = params[:name].to_s.strip.downcase
  end

  def render_error(code)
    render json: { swift_code: nil, error: code.to_s }, status: :ok
  end
end
