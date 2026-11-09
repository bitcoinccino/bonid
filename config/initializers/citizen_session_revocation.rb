# frozen_string_literal: true

# "Sign out everywhere" for citizens.
#
# Every citizen session remembers the User#session_version it was issued under.
# Bumping the version (User#revoke_all_citizen_sessions!) drops every other
# session on its next request. Sessions issued before this shipped carry no
# version and are treated as version 0 so nobody is logged out by the deploy.
Warden::Manager.after_set_user except: :fetch, scope: :citizen do |user, warden, _opts|
  next unless user.respond_to?(:session_version)

  warden.session(:citizen)["session_version"] = user.session_version
end

Warden::Manager.after_set_user only: :fetch, scope: :citizen do |user, warden, _opts|
  next unless user.respond_to?(:session_version)

  stored = warden.session(:citizen)["session_version"] || 0
  next if stored == user.session_version

  warden.logout(:citizen)
  throw :warden, scope: :citizen, message: :session_revoked
end
