# app/services/consent_scope_resolver.rb
class ConsentScopeResolver
  def self.resolve(scope_key)
    CONSENT_SCOPES[scope_key] || {}
  end

  def self.attributes_for(scope_key)
    models = CONSENT_SCOPES.dig(scope_key, :models) || {}
    models.transform_values do |attrs|
      attrs.select do |attr|
        model_klass = attr.constantize rescue nil
        model_klass&.column_names&.include?(attr)
      end
    end
  end
end
