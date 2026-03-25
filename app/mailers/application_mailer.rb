class ApplicationMailer < ActionMailer::Base
  default from: "noreply@verifyem.ht"
  layout nil   # Devise won't render anything since we override all mailers
end
