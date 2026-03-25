# app/helpers/partner_portal/embassy/dashboard_helper.rb
module PartnerPortal::Embassy::DashboardHelper
  def api_status_badge(success)
    if success
      content_tag(:span, "Success", class: "badge bg-success")
    else
      content_tag(:span, "Throttled", class: "badge bg-danger")
    end
  end
end
