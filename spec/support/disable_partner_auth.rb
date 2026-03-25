# frozen_string_literal: true

RSpec.configure do |config|
  config.before(:each, type: :request) do
    # Ensure base controller is loaded
    require Rails.root.join("app/controllers/api/v1/base_controller")

    next unless defined?(Api::V1::BaseController)

    # ✅ Stub both authenticators (whichever is used)
    allow_any_instance_of(Api::V1::BaseController)
      .to receive(:authenticate_partner!).and_return(true)

    allow_any_instance_of(Api::V1::BaseController)
      .to receive(:authenticate_partner_or_token!).and_return(true)
  end
end
