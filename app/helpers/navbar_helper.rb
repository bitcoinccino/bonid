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
          # Paused for v1 (focus on BonID): IDPol, BonVote and BonTouris are
          # left out of the menu entirely until IDPOL_ENABLED /
          # BONVOTE_ENABLED / BONTOURIS_ENABLED are turned on.
          (if idpol_enabled?
            {
              name: "IDPol",
              description: t("main.navbar.idpol_desc"),
              icon: "ri-shield-user-line",
              path: new_officer_session_path,
              # Shown but not clickable yet (the dropdown renders disabled items as a span).
              disabled: true,
              **soon_badge
            }
          end),
          (if bonvote_enabled?
            {
              name: "BonVote",
              description: t("main.navbar.bonvote_desc"),
              icon: "ri-checkbox-circle-line",
              path: "/election/verify",
              **new_badge
            }
          end),
          (if bontouris_enabled?
            {
              name: "BonTouris",
              description: t("main.navbar.bontouris_desc"),
              icon: "ri-suitcase-3-line",
              path: new_public_visitor_path,
              **new_badge
            }
          end)
        ].compact
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
    ].reject { |g| g[:items].empty? } # no heading over an empty group (BonGouv while paused)
  end

  # Keep backwards-compat for any other views that call core_products
  def core_products
    product_groups.flat_map { |g| g[:items] }
  end

  def getting_started_links
    [
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
