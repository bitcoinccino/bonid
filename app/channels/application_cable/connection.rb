# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_citizen

    def connect
      self.current_citizen = find_verified_citizen
    end

    private

    def find_verified_citizen
      citizen = nil
      # Devise :timeoutable can `throw :warden` when the session has expired.
      # ActionCable runs outside Warden's catch block, so wrap it and treat an
      # expired/invalid session as simply unauthenticated (reject the socket).
      catch(:warden) { citizen = env["warden"].user(:citizen) }
      citizen || reject_unauthorized_connection
    end
  end
end
