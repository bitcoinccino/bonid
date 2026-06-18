# frozen_string_literal: true

module NavbarHelper
  def product_groups
    new_badge  = { badge: t("main.navbar.new_badge"),    badge_class: "navbar-badge-new" }
    soon_badge = { badge: t("main.navbar.coming_badge"), badge_class: "navbar-badge-soon" }

    [
      {
        label_key: "main.navbar.identity",
        items: [
          {
            name: "BonID",
            description: t("main.navbar.bonid_desc"),
            icon: "ri-id-card-line",
            path: login_path,
            **new_badge
          }
        ]
      },
      {
        label_key: "main.navbar.government",
        items: [
          {
            name: "IDPol",
            description: t("main.navbar.idpol_desc"),
            icon: "ri-shield-user-line",
            path: new_officer_session_path,
            **new_badge
          },
          {
            name: "BonVote",
            description: t("main.navbar.bonvote_desc"),
            icon: "ri-checkbox-circle-line",
            path: "/election/verify",
            **soon_badge
          }
        ]
      },
      {
        label_key: "main.navbar.developers",
        items: [
          {
            name: "API",
            description: t("main.navbar.api_desc"),
            icon: "ri-code-s-slash-line",
            path: "/api-docs/index.html"
          }
        ]
      }
    ]
  end

  # Keep backwards-compat for any other views that call core_products
  def core_products
    product_groups.flat_map { |g| g[:items] }
  end

  def getting_started_links
    [
      {
        title: t("main.navbar.create_bonid"),
        description: t("main.navbar.create_bonid_desc"),
        icon: "ri-user-add-line",
        path: home_anchor("enskri"),
        data: { enskri: "citizen" }
      },
      {
        title: t("main.navbar.become_partner"),
        description: t("main.navbar.become_partner_desc"),
        icon: "ri-building-2-line",
        path: home_anchor("enskri"),
        data: { enskri: "business" }
      }
    ]
  end

  def main_navigation_links
    [
      {
        title: t("main.navbar.how_it_works"),
        path: home_anchor("how-it-works"),
        classes: "",
        icon: nil,
        icon_wrapper: false
      },
      {
        title: t("main.navbar.faq"),
        path: home_anchor("faq"),
        classes: "",
        icon: nil,
        icon_wrapper: false
      },
      {
        title: t("main.navbar.join"),
        path: home_anchor("enskri"),
        classes: "d-flex align-items-center",
        icon: "ri-user-add-line",
        icon_wrapper: true,
        data: { enskri: "citizen" }
      }
    ]
  end

  private

  # Returns a same-page anchor (#foo) when the visitor is already on the
  # home page, and an absolute /#foo path otherwise so the browser can
  # navigate to the home page and scroll to the section. This is what
  # makes the nav links (How It Works / FAQ / Join) clickable from
  # /partners, /pricing, /privacy, /terms, etc.
  def home_anchor(id)
    current_page?(root_path) ? "##{id}" : "#{root_path}##{id}"
  end
end
