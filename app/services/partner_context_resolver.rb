# app/services/partner_context_resolver.rb
class PartnerContextResolver
  attr_reader :partner, :sector, :slug

  def initialize(resource)
    @resource = resource
    resolve!
  end

  def resolve!
    @partner = detect_partner
    @sector  = @partner&.sector&.to_s&.downcase
    @slug    = @partner&.slug
  end

  def detect_partner
    return @resource.partner if @resource.respond_to?(:partner)
    return @resource.current_partner_admin.partner if @resource.respond_to?(:current_partner_admin)
    return @resource.partner_admin.partner if @resource.respond_to?(:partner_admin)
    nil
  rescue => e
    Rails.logger.error("PartnerContextResolver failed: #{e.message}")
    nil
  end

  # 🚨 THIS METHOD FIXES THE ERROR
  # It allows middleware to safely call PartnerContextResolver.call(nil)
  def self.call(resource = nil)
    if resource.nil?
      Rails.logger.warn("[PartnerContextResolver] called with nil resource — returning empty context")
      return new(OpenStruct.new)
    end

    new(resource)
  rescue => e
    Rails.logger.error("[PartnerContextResolver.call] failed: #{e.class} - #{e.message}")
    new(OpenStruct.new)
  end
end
