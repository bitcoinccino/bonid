# # frozen_string_literal: true

# # === Rolify Safe Empty Patch ===
# # Prevents NoMethodError: undefined method `empty?' for <User or BankingAgent>
# # which occurs during Devise + Rolify interaction when resource is nil/new.
# #
# # This ensures that any accidental call to `.empty?` on a role or model
# # safely returns false instead of raising an error.
# # frozen_string_literal: true

# # === Rolify Safe Empty Patch ===
# # Fixes "undefined method `empty?`" errors that occur
# # during Devise + Rolify interaction when resources are nil or new.
# #
# #  Only applied to Rolify-related models (NOT globally).

# module RolifySafeEmptyPatch
#   def method_missing(method, *args, &block)
#     # Only handle the `empty?` edge case
#     return false if method == :empty?

#     super
#   end
# end

# # === Apply only to Rolify::Role ===
# if defined?(Rolify::Role)
#   Rolify::Role.prepend(RolifySafeEmptyPatch)
# end

# # === Apply to Rolify-enabled models only ===
# ActiveSupport.on_load(:active_record) do
#   Rails.application.config.to_prepare do
#     ActiveRecord::Base.descendants.each do |model|
#       next unless model.included_modules.map(&:to_s).include?("Rolify")

#       model.prepend(RolifySafeEmptyPatch) unless model < RolifySafeEmptyPatch
#     end
#   end
# end
