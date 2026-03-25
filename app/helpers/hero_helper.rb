#  ================================
#  app/helpers/hero_helper.rb
# =================================== -->

module HeroHelper
  def verification_examples
    [
      {
        image: "partners/hero_scan_sample.svg",
        name: "Jean-Pierre Louis",
        verified_via: "Unibank",
        icon: "ri-bank-card-line"
      },
      {
        image: "partners/hero_scan_sample3.svg",
        name: "Marie-Claire Joseph",
        verified_via: "U.S. Embassy",
        icon: "ri-building-4-line"
      },
      {
        image: "partners/hero_scan_sample4.svg",
        name: "Robert Voltaire",
        verified_via: "Police Nationale d'Haïti (PNH)",
        icon: "ri-shield-check-line"
      }
    ]
  end
end
