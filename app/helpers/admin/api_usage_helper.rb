module Admin::ApiUsageHelper
  def status_badge_class(status)
    case status.to_s
    when "success"
      "badge bg-success"
    when "client_error"
      "badge bg-warning"
    when "server_error"
      "badge bg-danger"
    else
      "badge bg-secondary"
    end
  end

  def truncate_endpoint(endpoint, length: 50)
    endpoint.to_s.truncate(length)
  end
end
