# frozen_string_literal: true

module PartnerPortal
  module BankingAgentsHelper
    # Builds a sidebar link that automatically highlights when active
    def sidebar_link_to(name, path, icon_class)
      active_class =
        current_page?(path) ? "active" :
        (request.path.start_with?(path) ? "active" : "")

      link_to path,
              class: "nav-link d-flex align-items-center text-dark gap-2 sidebar-link #{active_class}" do
        concat content_tag(:i, "", class: "#{icon_class} text-primary")
        concat content_tag(:span, name)
      end
    end
  end
end
