# frozen_string_literal: true

class AddMissingFieldsToVisitorSubmissions < ActiveRecord::Migration[8.0]
  def change
    # --- Identity ---
    add_column :visitor_submissions, :title, :string unless column_exists?(:visitor_submissions, :title)
    add_column :visitor_submissions, :middle_name, :string unless column_exists?(:visitor_submissions, :middle_name)
    add_column :visitor_submissions, :nationality, :string unless column_exists?(:visitor_submissions, :nationality)
    add_column :visitor_submissions, :residence_country, :string unless column_exists?(:visitor_submissions, :residence_country)

    # --- Contact ---
    add_column :visitor_submissions, :email, :string unless column_exists?(:visitor_submissions, :email)
    add_column :visitor_submissions, :phone, :string unless column_exists?(:visitor_submissions, :phone)

    # --- Transportation ---
    add_column :visitor_submissions, :transport_provider, :string, null: false, default: '' unless column_exists?(:visitor_submissions, :transport_provider)
    add_column :visitor_submissions, :transport_details, :jsonb, default: {} unless column_exists?(:visitor_submissions, :transport_details)

    # --- Indexes ---
    add_index :visitor_submissions, :transport_provider unless index_exists?(:visitor_submissions, :transport_provider)
    add_index :visitor_submissions, [ :entry_mode, :transport_provider ] unless index_exists?(:visitor_submissions, [ :entry_mode, :transport_provider ])
    add_index :visitor_submissions, :email unless index_exists?(:visitor_submissions, :email)
  end
end
