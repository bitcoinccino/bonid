RSpec.configure do |config|
  config.before(:suite) do
    unless ActionController::Base.method_defined?(:verify_authenticity_token)
      ActionController::Base.define_method(:verify_authenticity_token) { }
    end
  end
end
