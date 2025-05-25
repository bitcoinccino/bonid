# -*- encoding: utf-8 -*-
# stub: rqrcode_png 0.1.5 ruby lib

Gem::Specification.new do |s|
  s.name = "rqrcode_png".freeze
  s.version = "0.1.5".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Dan Carper".freeze]
  s.date = "2014-11-01"
  s.description = "Glues rQRCode together with chunky_png".freeze
  s.email = ["djcarper@me.com".freeze]
  s.homepage = "".freeze
  s.licenses = ["MIT".freeze]
  s.rubygems_version = "2.2.2".freeze
  s.summary = "Produces a .png from a given QR Code".freeze

  s.installed_by_version = "3.5.23".freeze

  s.specification_version = 4

  s.add_development_dependency(%q<rake>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<chunky_png>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<rqrcode>.freeze, [">= 0".freeze])
end
