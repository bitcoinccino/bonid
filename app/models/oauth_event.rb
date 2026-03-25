class OauthEvent < ApplicationRecord
  belongs_to :oauth_application
  belongs_to :user, optional: true
end
