# frozen_string_literal: true

class Current < ActiveSupport::CurrentAttributes
  attribute :user, :partner, :request

  def actor_id
    user&.id || partner&.id || "system"
  end

  def actor_type
    user ? "User" : (partner ? "Partner" : "System")
  end
end
