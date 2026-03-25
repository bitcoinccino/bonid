# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_citizen

    def connect
      self.current_citizen = find_verified_citizen
    end

    private

    def find_verified_citizen
      citizen = env["warden"].user(:citizen)
      citizen || reject_unauthorized_connection
    end
  end
end
