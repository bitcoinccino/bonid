# frozen_string_literal: true

module NavbarHelper
  def product_groups
    [
      {
        label_key: "main.navbar.identity",
        items: [
          {
            name: "BonID",
            description: t("main.navbar.bonid_desc"),
            icon: "ri-id-card-line",
            path: citizens_otp_sign_in_path
          },
          {
            name: "BonTouris",
            description: t("main.navbar.bontouris_desc"),
            icon: "ri-suitcase-line",
            path: get_started_public_visitors_path
          }
        ]
      },
      {
        label_key: "main.navbar.government",
        items: [
          {
            name: "BonVote",
            description: t("main.navbar.bonvote_desc"),
            icon: "ri-checkbox-circle-line",
            path: "/election/verify",
            badge: t("main.navbar.bonvote_badge"),
            badge_class: "bg-success"
          },
          {
            name: "BonTax",
            description: t("main.navbar.bontax_desc"),
            icon: "ri-money-dollar-circle-line",
            path: "#",
            badge: t("main.navbar.coming_badge"),
            badge_class: "bg-success"
          },
          {
            name: "BonTè",
            description: t("main.navbar.bonte_desc"),
            icon: "ri-map-pin-line",
            path: "#",
            badge: t("main.navbar.coming_badge"),
            badge_class: "bg-success"
          }
        ]
      },
      {
        label_key: "main.navbar.security",
        items: [
          {
            name: "IDPol",
            description: t("main.navbar.idpol_desc"),
            icon: "ri-shield-user-line",
            path: new_officer_session_path
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
        path: "#enskri",
        data: { enskri: "citizen" }
      },
      {
        title: t("main.navbar.become_partner"),
        description: t("main.navbar.become_partner_desc"),
        icon: "ri-building-2-line",
        path: "#enskri",
        data: { enskri: "business" }
      }
    ]
  end

  def main_navigation_links
    [
      {
        title: t("main.navbar.how_it_works"),
        path: "#how-it-works",
        classes: "",
        icon: nil,
        icon_wrapper: false
      },
      {
        title: t("main.navbar.faq"),
        path: "#faq",
        classes: "",
        icon: nil,
        icon_wrapper: false
      },
      {
        title: t("main.navbar.join"),
        path: "#enskri",
        classes: "d-flex align-items-center",
        icon: "ri-user-add-line",
        icon_wrapper: true,
        data: { enskri: "citizen" }
      }
    ]
  end
end
