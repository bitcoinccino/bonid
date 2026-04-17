# frozen_string_literal: true

class AddDraftAndPublishToPartnerSchemas < ActiveRecord::Migration[8.0]
  def change
    add_column :partner_schemas, :draft_structure, :jsonb         # working copy while editing
    add_column :partner_schemas, :published_at, :datetime         # when current version went live
    add_column :partner_schemas, :schema_status, :string, default: "draft" # draft, published, archived

    add_index :partner_schemas, [ :partner_id, :record_type, :schema_status ], name: "idx_schemas_partner_record_status"
  end
end
