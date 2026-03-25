# frozen_string_literal: true

# spec/support/api_auth_helpers.rb
RSpec.configure do |config|
  # 🔒 Skip partner, API key, and BonID authentication for request specs
  config.before(:each, type: :request) do
    # Stub partner authentication
    allow_any_instance_of(Api::V1::BaseController)
      .to receive(:authenticate_partner!)
      .and_return(true)

    # Stub API key authentication – COMMENTED: Let headers auth naturally in tests
    # allow_any_instance_of(Api::V1::BaseController)
    #   .to receive(:authenticate_api_key!)
    #   .and_return(true)

    # Stub BonID-specific API authentication if called in tests
    [ :authenticate_citizen!, :authenticate_officer! ].each do |method|
      allow_any_instance_of(Api::V1::BaseController)
        .to receive(method)
        .and_return(true)
    end
  end
end

# # frozen_string_literal: true

# # spec/support/api_auth_helpers.rb
# RSpec.configure do |config|
#   # 🔒 Skip partner, API key, and BonID authentication for request specs
#   config.before(:each, type: :request) do
#     # Stub partner authentication
#     allow_any_instance_of(Api::V1::BaseController)
#       .to receive(:authenticate_partner!)
#       .and_return(true)

#     # Stub API key authentication
#     allow_any_instance_of(Api::V1::BaseController)
#       .to receive(:authenticate_api_key!)
#       .and_return(true)

#     # Stub BonID-specific API authentication if called in tests
#     [ :authenticate_citizen!, :authenticate_officer! ].each do |method|
#       allow_any_instance_of(Api::V1::BaseController)
#         .to receive(method)
#         .and_return(true)
#     end
#   end
# end
