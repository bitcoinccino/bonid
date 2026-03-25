# frozen_string_literal: true

module NavbarHelper
  def core_products
    [
      {
        name: "BonID",
        description: t("main.navbar.bonid_desc"),
        icon: "ri-id-card-line",
        path: citizens_otp_sign_in_path,
        highlight: "",
        badge: nil,
        badge_class: nil
      },
      {
        name: "IDPol",
        description: t("main.navbar.idpol_desc"),
        icon: "ri-shield-user-line",
        path: new_officer_session_path,
        highlight: "",
        badge: nil,
        badge_class: nil
      },
      {
        name: "BonTouris",
        description: t("main.navbar.bontouris_desc"),
        icon: "ri-suitcase-line",
        path: get_started_public_visitors_path,
        highlight: "",
        badge: nil,
        badge_class: nil
      },
      {
        name: "BonVote",
        description: t("main.navbar.bonvote_desc"),
        icon: "ri-checkbox-circle-line",
        path: "/election/verify",
        highlight: "",
        badge: t("main.navbar.bonvote_badge"),
        badge_class: "bg-success"
      },
      {
        name: "API",
        description: t("main.navbar.api_desc"),
        icon: "ri-code-s-slash-line",
        path: "/api-docs/index.html",
        highlight: "",
        badge: nil,
        badge_class: nil
      }
    ]
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
