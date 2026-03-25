# Stub Role and Partner Context for router to prevent spec failures
RSpec.configure do |config|
  config.before(:each) do
    allow_any_instance_of(RoleContextResolver)
      .to receive(:current_role).and_return(:citizen)

    allow_any_instance_of(PartnerContextResolver)
      .to receive(:sector).and_return(nil)

    allow_any_instance_of(PartnerContextResolver)
      .to receive(:partner).and_return(nil)
  end
end
