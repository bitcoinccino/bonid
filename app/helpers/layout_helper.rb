# app/helpers/layout_helper.rb
module LayoutHelper
  def navbar_partial_for(sector)
    case sector
    when "Law Enforcement"
      "partner_law_navbar"
    when "Government Services", "Embassy Services Verification", "Embassy"
      "partner_embassy_navbar"
    else
      "partner_navbar"
    end
  end
end
