# Ensure User/Citizen role attribute exists for specs that pass `role:` to factories.
# User uses rolify (not an enum column), so we declare a virtual attribute
# to prevent Rails 8 from raising "Undeclared attribute type for enum 'role'".
RSpec.configure do |config|
  config.before(:suite) do
    unless User.respond_to?(:roles)
      User.class_eval do
        attribute :role, :string
      end
    end
  end
end
