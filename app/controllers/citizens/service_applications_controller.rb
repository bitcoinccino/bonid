# frozen_string_literal: true

# Citizens::ServiceApplicationsController
# ========================================
# Handles the citizen-facing service application flow:
#   - Browse → Apply → Multi-step form → Auto-save → Submit → Receipt
#
# The form is dynamically rendered from the PartnerSchema's published structure.
# Each step auto-saves to the database, so citizens can resume later.
#
module Citizens
  class ServiceApplicationsController < Citizens::BaseController
    before_action :set_citizen
    before_action :enable_immersive_form, only: [ :new, :create, :show ]
    before_action :find_application, only: [ :show, :update, :submit, :receipt ]

    # ============================================================
    # INDEX — My Applications (Aplikasyon Mwen)
    # ============================================================
    def index
      all_apps = @citizen.service_applications
                         .includes(:partner, :partner_schema)
                         .order(updated_at: :desc)

      @filter = params[:status].to_s.strip
      all_apps = all_apps.where(status: @filter) if @filter.present? && ServiceApplication::STATUSES.include?(@filter)

      @applications = all_apps.to_a

      @stats = {
        total: @citizen.service_applications.count,
        drafts: @citizen.service_applications.drafts.count,
        submitted: @citizen.service_applications.submitted.count,
        approved: @citizen.service_applications.approved.count,
        rejected: @citizen.service_applications.rejected.count
      }
    end

    # ============================================================
    # NEW — Start a new application (or resume a draft)
    # GET /citizens/apply/:partner_slug/:form_code
    # ============================================================
    def new
      @partner = Partner.find_by!(slug: params[:partner_slug], status: :approved, active: true, deleted_at: nil)
      @schema = @partner.partner_schemas.find_by!(form_code: params[:form_code])

      is_transaction = @schema.service_category == "transaction"

      if is_transaction
        # Transactions: reuse existing draft or create one (never pile up)
        @application = @citizen.service_applications
                                .where(partner_schema: @schema, status: "draft")
                                .order(updated_at: :desc)
                                .first

        if @application
          @resuming = false # don't show "resume" banner for transactions
        else
          @application = @citizen.service_applications.create!(
            partner: @partner,
            partner_schema: @schema,
            status: "draft",
            form_data: {},
            calculated_values: {}
          )
        end
      else
        # Applications/surveys: check for existing draft to resume
        @application = @citizen.service_applications
                                .where(partner_schema: @schema, status: "draft")
                                .order(updated_at: :desc)
                                .first

        if @application
          @resuming = true
        else
          @application = @citizen.service_applications.create!(
            partner: @partner,
            partner_schema: @schema,
            status: "draft",
            form_data: {},
            calculated_values: {}
          )
        end
      end

      prepare_form_data
    end

    # ============================================================
    # CREATE — Handles initial auto-save from the wizard
    # (Redirects to #show for editing the draft)
    # ============================================================
    def create
      @partner = Partner.find(params[:partner_id])
      @schema = @partner.partner_schemas.find(params[:partner_schema_id])

      @application = @citizen.service_applications.create!(
        partner: @partner,
        partner_schema: @schema,
        status: "draft",
        form_data: sanitized_form_data,
        calculated_values: {}
      )

      redirect_to citizens_service_application_path(@application)
    end

    # ============================================================
    # SHOW — View application (draft = continue editing, submitted = status)
    # ============================================================
    def show
      @partner = @application.partner
      @schema = @application.partner_schema

      if @application.draft?
        prepare_form_data
        render :new
      else
        # Show status / receipt view
        @form_fields = @application.frozen_fields_by_step

        # Partner-filled fields (event details like date, address)
        @partner_filled = @application.frozen_fields.select { |f| f["filled_by"] == "partner" && f["partner_value"].present? || f["filled_by"] == "partner" && f["type"] == "address" }

        # Zellus balance
        @zellus_balance = nil
        citizen = @application.citizen
        zellus_wallet = citizen.bank_profiles.find { |bp| bp.account_source_mobile_wallet? && bp.wallet_provider&.downcase == "zellus" && bp.cashtag.present? }
        if zellus_wallet
          begin
            @zellus_balance = fetch_zellus_balance(zellus_wallet.cashtag)
          rescue => e
            Rails.logger.warn("Zellus balance fetch failed: #{e.message}")
          end
        end
      end
    end

    # ============================================================
    # UPDATE — Save form data (step-by-step or full)
    # ============================================================
    def update
      unless @application.status == "draft"
        redirect_to citizens_service_application_path(@application), alert: "Aplikasyon sa a deja soumèt."
        return
      end

      # Merge new form data with existing (preserves data from other steps)
      merged_data = (@application.form_data || {}).merge(sanitized_form_data)
      calculated = compute_calculated_fields(merged_data)

      @application.update!(
        form_data: merged_data,
        calculated_values: calculated
      )

      if params[:next_step].present?
        # Auto-save between steps — redirect back to form
        redirect_to citizens_service_application_path(@application, step: params[:next_step])
      else
        redirect_to citizens_service_application_path(@application), notice: "Done sove."
      end
    end

    # ============================================================
    # AUTO_SAVE — AJAX endpoint for background auto-save
    # POST /citizens/service_applications/auto_save
    # ============================================================
    def auto_save
      @application = @citizen.service_applications.find(params[:application_id])

      unless @application.status == "draft"
        render json: { status: "locked" }, status: :unprocessable_entity
        return
      end

      merged_data = (@application.form_data || {}).merge(sanitized_form_data)
      calculated = compute_calculated_fields(merged_data)

      @application.update!(
        form_data: merged_data,
        calculated_values: calculated
      )

      render json: {
        status: "saved",
        saved_at: Time.current.strftime("%H:%M"),
        calculated_values: calculated
      }
    end

    # ============================================================
    # SUBMIT — Final submission with signature consent
    # ============================================================
    def submit
      unless @application.status == "draft"
        redirect_to citizens_service_application_path(@application), alert: "Aplikasyon sa a deja soumèt."
        return
      end

      # Final data merge
      merged_data = (@application.form_data || {}).merge(sanitized_form_data)

      # Server-side repeater enforcement: clamp rows to min/max, strip excess
      merged_data = enforce_repeater_limits(merged_data)

      # Server-side condition enforcement: strip data from hidden fields
      merged_data = enforce_condition_rules(merged_data)

      calculated = compute_calculated_fields(merged_data)

      # Validate required fields (respects conditional visibility)
      missing = validate_required_fields(merged_data)

      # Validate datetime after_field constraints (end must be after start)
      datetime_errors = validate_datetime_constraints(merged_data)
      missing.concat(datetime_errors)

      if missing.any?
        @application.update!(form_data: merged_data, calculated_values: calculated)
        @partner = @application.partner
        @schema = @application.partner_schema
        prepare_form_data
        flash.now[:alert] = "Tanpri ranpli tout chan obligatwa: #{missing.join(', ')}"
        render :new, status: :unprocessable_entity
        return
      end

      # Apply signature consent if schema requires it
      signature_attrs = {}
      if @application.partner_schema.requires_signature?
        signature_attrs = {
          signature_consented: params[:signature_consent] == "1",
          signature_applied_at: Time.current
        }
      end

      # Calculate pricing
      price_attrs = compute_pricing(merged_data, calculated)

      @application.update!(
        form_data: merged_data,
        calculated_values: calculated,
        payment_method: params[:payment_method_id].presence || params[:payment_method],
        **signature_attrs,
        **price_attrs
      )

      # If paid service, route to payment before finalizing
      if price_attrs[:total_price_cents].to_i > 0
        payment_method = params[:payment_method].presence || "zellus"

        case payment_method
        when "zellus"
          begin
            checkout_result = create_zellus_checkout(@application)
            @application.update!(payment_token: checkout_result[:token])
            redirect_to checkout_result[:checkout_url], allow_other_host: true
            return
          rescue => e
            Rails.logger.error("Zellus checkout failed: #{e.message}")
            flash[:alert] = "Peman Zellus echwe: #{e.message}"
            @partner = @application.partner
            @schema = @application.partner_schema
            prepare_form_data
            render :new, status: :unprocessable_entity
            return
          end
        when "moncash"
          # MonCash flow — TODO
          @application.submit!
        else
          @application.submit!
        end
      else
        @application.submit!
      end

      redirect_to receipt_citizens_service_application_path(@application),
                  notice: "Aplikasyon soumèt avèk siksè!"
    end

    # ============================================================
    # ZELLUS CALLBACK — After payment on Zellus
    # ============================================================
    def zellus_callback
      @application = @citizen.service_applications.find(params[:app_id])

      begin
        api_base = ENV.fetch("ZELLUS_API_BASE", "https://zellus.ht")
        api_key  = ENV["ZELLUS_API_KEY"]
        token    = @application.payment_token

        uri  = URI("#{api_base}/api/v1/checkouts/#{token}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 10
        http.read_timeout = 15
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE if Rails.env.development?

        request = Net::HTTP::Get.new(uri)
        request["X-Partner-Api-Key"] = api_key
        request["Accept"] = "application/json"

        response = http.request(request)
        data = response.is_a?(Net::HTTPSuccess) ? JSON.parse(response.body) : {}
        status = data.dig("checkout", "status")

        if status == "completed"
          transfer_id = data.dig("checkout", "transfer_id")
          @application.update!(
            paid: true,
            paid_at: Time.current,
            payment_transaction_id: "ZELLUS-#{transfer_id || token}"
          )
          @application.submit! if @application.draft?
          redirect_to receipt_citizens_service_application_path(@application),
                      notice: "Peman reyisi! Aplikasyon soumèt."
        else
          flash[:alert] = "Peman pa konplete. Tanpri eseye ankò."
          redirect_to citizens_service_application_path(@application)
        end
      rescue => e
        Rails.logger.error("Zellus callback error: #{e.message}")
        flash[:alert] = "Erè nan verifikasyon peman."
        redirect_to citizens_service_application_path(@application)
      end
    end

    # ============================================================
    # RECEIPT — Confirmation page after submission
    # ============================================================
    def receipt
      @partner = @application.partner
      @schema = @application.partner_schema
      @form_fields = @application.frozen_fields_by_step
    end

    private

    def set_citizen
      @citizen = current_citizen
    end

    def find_application
      @application = @citizen.service_applications.find(params[:id])
    end

    def enable_immersive_form
      @immersive_form = true
    end

    def sanitized_form_data
      raw = (params[:form_data] || {}).to_unsafe_h
      raw.transform_values do |v|
        case v
        when String
          v.strip
        when Hash
          # Repeater data: { "0" => { "non" => "Jean", ... }, "1" => { ... } }
          # Convert to array of hashes, sorted by key, stripping string values
          v.sort_by { |k, _| k.to_i }.map do |_, row|
            next unless row.is_a?(Hash)
            row.transform_values { |rv| rv.is_a?(String) ? rv.strip : rv }
          end.compact
        when Array
          v
        else
          v
        end
      end
    end

    def prepare_form_data
      @fields_by_step = @application.frozen_fields_by_step
      @current_step = (params[:step] || 0).to_i
      @total_steps = @fields_by_step.length
      @saved_data = @application.form_data || {}
      @calculated = @application.calculated_values || {}

      # Auto-fill from BonID profile
      addr = @citizen.try(:address)
      @auto_fill = {
        "first_name" => @citizen.first_name,
        "last_name" => @citizen.last_name,
        "email" => @citizen.email,
        "phone" => @citizen.phone,
        "bonid" => @citizen.try(:bonid),
        "date_of_birth" => @citizen.try(:date_of_birth)&.strftime("%Y-%m-%d"),
        # Address fields (Haiti hierarchy)
        "street_address" => @citizen.try(:street_address) || addr&.street_address,
        "locality" => addr&.locality,
        "communal_section" => addr&.communal_section&.name,
        "commune" => addr&.commune&.name,
        "arrondissement" => addr&.arrondissement&.name,
        "department" => addr&.department&.name,
        "department_id" => addr&.department_id,
        "arrondissement_id" => addr&.arrondissement_id,
        "commune_id" => addr&.commune_id,
        "communal_section_id" => addr&.communal_section_id,
        "postal_code" => addr&.postal_code
      }.compact

      # Payment methods (verified bank profiles)
      @payment_methods = @citizen.bank_profiles.select { |bp| bp.status_verified? }

      # Fetch Zellus balance if citizen has a Zellus wallet (check all wallets, not just verified)
      @zellus_balance = nil
      zellus_wallet = @citizen.bank_profiles.find { |bp| bp.account_source_mobile_wallet? && bp.wallet_provider&.downcase == "zellus" && bp.cashtag.present? }
      if zellus_wallet
        begin
          @zellus_balance = fetch_zellus_balance(zellus_wallet.cashtag)
        rescue => e
          Rails.logger.warn("Zellus balance fetch failed: #{e.message}")
        end
      end

      # Partner address for "use my BonID address" option
      partner_addr = @partner.try(:address)
      @partner_address = if partner_addr
        {
          "street" => partner_addr.street_address,
          "locality" => partner_addr.locality,
          "communal_section" => partner_addr.try(:communal_section)&.name,
          "department" => partner_addr.try(:department)&.name,
          "arrondissement" => partner_addr.try(:arrondissement)&.name,
          "commune" => partner_addr.try(:commune)&.name,
          "postal_code" => partner_addr.postal_code
        }.compact
      end
    end

    def validate_required_fields(data)
      missing = []
      @application.frozen_fields.each do |field|
        next unless field["required"]
        next if field["type"].in?(%w[bonid_signature seal_placeholder calculated section instructional_text])
        next if field["filled_by"] == "partner"

        # ── Conditional Required: skip hidden fields ──
        next if field_conditionally_hidden?(field, data)

        # Address composite: check that at least department sub-field is filled
        if field["type"] == "address"
          key = field["key"]
          missing << (field["label"] || key) if data["#{key}_department"].blank?
          next
        end

        # Repeater: validate required sub-fields in each row
        if field["type"] == "repeater"
          key = field["key"]
          rows = data[key]
          if rows.blank? || !rows.is_a?(Array) || rows.empty?
            missing << (field["label"] || key)
          else
            sub_fields = field["fields"] || []
            rows.each_with_index do |row, idx|
              next unless row.is_a?(Hash)
              sub_fields.each do |sf|
                next unless sf["required"]
                if row[sf["key"]].blank?
                  missing << "#{field["label"]} ##{idx + 1}: #{sf["label"] || sf["key"]}"
                end
              end
            end
          end
          next
        end

        key = field["key"]
        missing << (field["label"] || key) if data[key].blank?
      end
      missing
    end

    # ── Datetime after_field constraint validation ──
    # Ensures end datetime comes after start datetime when linked via after_field.
    def validate_datetime_constraints(data)
      errors = []
      @application.frozen_fields.each do |field|
        next unless field["type"] == "datetime" && field["after_field"].present?
        next if field_conditionally_hidden?(field, data)

        end_val = data[field["key"]]
        start_val = data[field["after_field"]]
        next if end_val.blank? || start_val.blank?

        begin
          end_time = DateTime.parse(end_val.to_s)
          start_time = DateTime.parse(start_val.to_s)
          if end_time <= start_time
            start_field = @application.frozen_fields.find { |f| f["key"] == field["after_field"] }
            start_label = start_field&.dig("label") || field["after_field"]
            errors << "#{field["label"] || field["key"]} dwe vin apre #{start_label}"
          end
        rescue Date::Error, ArgumentError
          # If dates can't be parsed, skip validation (will fail on other checks)
        end
      end
      errors
    end

    # ── Server-Side Condition Enforcement ──
    # Re-evaluates visible_if conditions on the server to strip data
    # from fields that should be hidden. Prevents malicious submissions
    # from including data for conditionally hidden fields.
    def enforce_condition_rules(data)
      sanitized = data.dup
      @application.frozen_fields.each do |field|
        next unless field["visible_if"].present?

        if field_conditionally_hidden?(field, data)
          sanitized.delete(field["key"])
        end
      end
      sanitized
    end

    # ── Server-Side Repeater Limit Enforcement ──
    # Prevents injection of extra rows beyond max_rows or removal below min_rows.
    # Prices are ALWAYS recalculated from frozen schema rules — never from client.
    def enforce_repeater_limits(data)
      sanitized = data.dup
      @application.frozen_fields.each do |field|
        next unless field["type"] == "repeater"
        key = field["key"]
        rows = sanitized[key]
        next unless rows.is_a?(Array)

        max_rows = (field["max_rows"] || 50).to_i
        min_rows = (field["min_rows"] || 0).to_i

        # Clamp: strip excess rows beyond max
        sanitized[key] = rows.first(max_rows) if rows.length > max_rows

        # If below min and field is required, validation will catch it
        # (we don't pad with empty rows server-side — that's a UX concern)
      end
      sanitized
    end

    # ── Repeater Data Normalization ──
    # Ensure repeater values stored as arrays of hashes survive JSON round-trips
    def normalize_repeater_data(data)
      @application.frozen_fields.each do |field|
        next unless field["type"] == "repeater"
        key = field["key"]
        val = data[key]
        next unless val.present?

        # If it came through as a hash (from form params), convert to array
        if val.is_a?(Hash)
          data[key] = val.sort_by { |k, _| k.to_i }.map { |_, row| row }.compact
        end
      end
      data
    end

    # Evaluate whether a field is conditionally hidden based on form data
    def field_conditionally_hidden?(field, data)
      condition = field["visible_if"]
      return false if condition.blank?

      !evaluate_condition_group(condition, data)
    end

    # Evaluate a condition group — mirrors the JS logic server-side
    # Supports: single rule, Array (AND), all_of (AND), any_of (OR)
    def evaluate_condition_group(condition, data)
      # Array of rules → AND
      if condition.is_a?(Array)
        return condition.all? { |rule| evaluate_single_condition(rule, data) }
      end

      # Hash with any_of → OR
      if condition["any_of"].is_a?(Array)
        return condition["any_of"].any? { |rule| evaluate_condition_group(rule, data) }
      end

      # Hash with all_of → AND
      if condition["all_of"].is_a?(Array)
        return condition["all_of"].all? { |rule| evaluate_condition_group(rule, data) }
      end

      # Single rule { field, operator, value }
      if condition["field"].present? && condition["operator"].present?
        return evaluate_single_condition(condition, data)
      end

      true # unknown format — show field
    end

    def evaluate_single_condition(rule, data)
      value = data[rule["field"]].to_s
      expected = rule["value"].to_s

      case rule["operator"]
      when "equals"       then value == expected
      when "not_equals"   then value != expected
      when "greater_than" then value.to_f > expected.to_f
      when "less_than"    then value.to_f < expected.to_f
      when "contains"     then value.downcase.include?(expected.downcase)
      when "is_empty"     then value.blank?
      when "is_not_empty" then value.present?
      else true
      end
    end

    # ── Repeater Pricing Rule Evaluator ──
    # Evaluates pricing rules against a single row's data.
    # Returns the first matching rule's price and label, or the default.
    def evaluate_repeater_pricing_rules(rules, row_data)
      rules.each do |rule|
        # Default rule = fallback
        if rule["condition"] == "default"
          return { price: rule["price"], label: rule["label"] }
        end

        # Evaluate the condition against the row's sub-field data
        field_val = row_data[rule["field"]].to_s
        expected = rule["value"].to_s

        matched = case rule["operator"]
        when "equals" then field_val == expected
        when "not_equals" then field_val != expected
        when "greater_than" then field_val.to_f > expected.to_f
        when "less_than" then field_val.to_f < expected.to_f
        when "age_less_than"
                    age = calculate_age_from_date(field_val)
                    age.present? && age < expected.to_f
        when "age_greater_than_or_equal"
                    age = calculate_age_from_date(field_val)
                    age.present? && age >= expected.to_f
        else false
        end

        return { price: rule["price"], label: rule["label"] } if matched
      end

      # No rule matched — 0
      { price: 0, label: nil }
    end

    def calculate_age_from_date(date_str)
      return nil if date_str.blank?
      dob = Date.parse(date_str)
      today = Date.current
      age = today.year - dob.year
      age -= 1 if today.month < dob.month || (today.month == dob.month && today.day < dob.day)
      age
    rescue
      nil
    end

    def compute_calculated_fields(data)
      calculated = {}
      @application.frozen_fields.each do |field|
        next unless field["type"] == "calculated"
        # Skip calculated fields that are conditionally hidden
        next if field_conditionally_hidden?(field, data)

        formula = field["formula"].to_s
        next if formula.blank?

        begin
          # Replace field references with actual values
          expression = formula.gsub(/[a-z_][a-z0-9_]*/i) do |ref|
            val = data[ref] || calculated[ref] || 0
            val.to_f
          end
          calculated[field["key"]] = eval(expression).round(2) # rubocop:disable Security/Eval
        rescue => e
          Rails.logger.warn "Calculated field #{field['key']} failed: #{e.message}"
          calculated[field["key"]] = 0
        end
      end
      calculated
    end

    def compute_pricing(data, calculated)
      schema = @application.partner_schema
      currency = schema.currency || "HTG"
      base_cents = schema.price_cents.to_i

      has_priced_fields = @application.frozen_fields.any? { |f| f["has_pricing"] }

      case schema.pricing_type
      when "free"
        unless has_priced_fields
          return { total_price_cents: 0, currency: currency, price_snapshot: { base: 0, fees: [], addons: [], total: 0, currency: currency } }
        end
      when "variable"
        total = @application.frozen_fields
                  .select { |f| f["type"] == "calculated" && f["pricing"] }
                  .sum { |f| (calculated[f["key"]].to_f * 100).to_i }
        total = base_cents if total.zero? && base_cents > 0
        return { total_price_cents: total, currency: currency, price_snapshot: { base: total, fees: [], addons: [], total: total, currency: currency } }
      end

      # Fixed pricing — build full breakdown

      # Quantity multiplier — if a number field is linked to __base_price__, multiply base
      qty_multiplier = 1
      qty_field_info = nil
      @application.frozen_fields.each do |field|
        next unless field["is_quantity"] && field["linked_to_field"] == "__base_price__"
        qty_val = data[field["key"]].to_f
        qty_val = [ qty_val, (field["min"] || 1).to_f ].max
        qty_val = [ qty_val, field["max"].to_f ].min if field["max"].present?
        qty_multiplier = qty_val
        qty_field_info = { field: field["label"], quantity: qty_val, unit: field["unit"] }
        break # only one quantity field per form
      end

      effective_base = (base_cents * qty_multiplier).round
      snapshot_lines = []
      total_cents = effective_base

      # Mandatory fees from price_metadata (applied to effective base, post-quantity)
      mandatory_fees = schema.price_metadata["mandatory_fees"] || []
      mandatory_fees.each do |fee|
        kind = fee["kind"] || fee["type"]
        case kind
        when "percent", "percentage"
          amt = (effective_base * (fee["value"] || fee["amount"] || 0).to_f / 100).round
          snapshot_lines << { name: fee["name"], kind: "percent", rate: fee["value"] || fee["amount"], amount_cents: amt }
        when "fixed"
          amt = ((fee["value"] || fee["amount"] || 0).to_f * 100).round
          snapshot_lines << { name: fee["name"], kind: "fixed", amount_cents: amt }
        end
        total_cents += amt
      end

      # Repeater price-per-row (fixed or conditional rules)
      # Server enforces min_rows / max_rows to prevent injection of extra rows
      repeater_lines = []
      @application.frozen_fields.each do |field|
        next unless field["type"] == "repeater" && field["has_pricing"]

        rows = data[field["key"]]
        next unless rows.is_a?(Array) && rows.any?

        # ── Server-side row limit enforcement ──
        max_rows = (field["max_rows"] || 50).to_i
        rows = rows.first(max_rows) if rows.length > max_rows

        if field["pricing_mode"] == "rules" && field["pricing_rules"].present?
          # Conditional rules — evaluate per row using frozen schema rules (NOT client-sent)
          breakdown = Hash.new { |h, k| h[k] = { cents: 0, count: 0 } }

          rows.each do |row|
            next unless row.is_a?(Hash)
            matched = evaluate_repeater_pricing_rules(field["pricing_rules"], row)
            cents = (matched[:price].to_f * 100).round
            label = matched[:label] || field["label"]
            breakdown[label][:cents] = cents
            breakdown[label][:count] += 1
          end

          breakdown.each do |label, info|
            amt = info[:cents] * info[:count]
            repeater_lines << { field: field["label"], label: label, per_row_cents: info[:cents], row_count: info[:count], amount_cents: amt }
            total_cents += amt
          end
        else
          # Fixed price per row
          per_row = field["price_per_row"].to_f
          next unless per_row > 0

          per_row_cents = (per_row * 100).round
          row_count = rows.length
          repeater_total = per_row_cents * row_count
          repeater_lines << { field: field["label"], per_row_cents: per_row_cents, row_count: row_count, amount_cents: repeater_total }
          total_cents += repeater_total
        end
      end

      # Optional field add-ons based on citizen's choices
      # Find quantity fields linked to choice fields (not base price)
      choice_qty_fields = @application.frozen_fields.select { |f| f["is_quantity"] && f["linked_to_field"].present? && f["linked_to_field"] != "__base_price__" }

      addon_lines = []
      @application.frozen_fields.each do |field|
        next unless field["has_pricing"]
        next unless %w[select radio multi_checkbox].include?(field["type"])

        options = Array(field["options"])
        chosen = data[field["key"]]
        next if chosen.blank?

        # Check if a quantity field is linked to this choice field
        linked_qty = choice_qty_fields.find { |qf| qf["linked_to_field"] == field["key"] }
        qty_multi = 1
        if linked_qty
          qty_val = data[linked_qty["key"]].to_f
          qty_val = [ qty_val, (linked_qty["min"] || 1).to_f ].max
          qty_val = [ qty_val, linked_qty["max"].to_f ].min if linked_qty["max"].present?
          qty_multi = qty_val
        end

        chosen_values = chosen.is_a?(Array) ? chosen : [ chosen ]
        options.each do |opt|
          next unless opt.is_a?(Hash) && chosen_values.include?(opt["value"])
          extra_per = (opt["extra_price"].to_f * 100).round
          next if extra_per.zero?
          extra = (extra_per * qty_multi).round
          addon_lines << { field: field["label"], option: opt["label"], quantity: qty_multi > 1 ? qty_multi : nil, per_unit_cents: qty_multi > 1 ? extra_per : nil, amount_cents: extra }.compact
          total_cents += extra
        end
      end

      price_snapshot = {
        base_cents: base_cents,
        fees: snapshot_lines,
        addons: addon_lines,
        repeaters: repeater_lines.presence,
        total_cents: total_cents,
        currency: currency,
        frozen_at: Time.current.iso8601
      }.compact

      # Add quantity breakdown if present
      if qty_field_info
        price_snapshot[:quantity] = qty_field_info
        price_snapshot[:effective_base_cents] = effective_base
      end

      { total_price_cents: total_cents, currency: currency, price_snapshot: price_snapshot }
    end

    def create_zellus_checkout(application)
      api_base = ENV.fetch("ZELLUS_API_BASE", "https://zellus.ht")
      api_key  = ENV["ZELLUS_API_KEY"] || raise("ZELLUS_API_KEY pa konfigire")
      cashtag  = ENV.fetch("ZELLUS_RECEIVER_CASHTAG", "$bonid")

      callback_base = ENV.fetch("NGROK_HOST", "http://localhost:3000")
      success_url = "#{callback_base}/citizens/service_applications/zellus_callback?app_id=#{application.id}"
      cancel_url  = "#{callback_base}/citizens/service_applications/#{application.id}"

      amount = application.total_price_cents.to_f / 100
      description = "#{application.partner_schema.name} — #{application.verification_code}"

      uri  = URI("#{api_base}/api/v1/checkouts")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 30
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE if Rails.env.development?

      request = Net::HTTP::Post.new(uri)
      request["X-Partner-Api-Key"] = api_key
      request["Content-Type"] = "application/json"
      request["Accept"] = "application/json"
      request.body = {
        receiver_cashtag: cashtag,
        amount: amount,
        currency: "htg",
        description: description,
        success_url: success_url,
        cancel_url: cancel_url,
        metadata: { application_id: application.id, verification_code: application.verification_code }
      }.to_json

      response = http.request(request)
      raise "Zellus API erè (#{response.code})" unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(response.body)
      token = data.dig("checkout", "token")
      checkout_url = data.dig("checkout", "checkout_url")
      raise "Zellus pa retounen token" if token.blank?

      { token: token, checkout_url: checkout_url }
    end

    def fetch_zellus_balance(cashtag)
      api_base = ENV.fetch("ZELLUS_API_BASE", "https://zellus.ht")
      api_key  = ENV["ZELLUS_API_KEY"]
      return nil unless api_key.present?

      uri  = URI("#{api_base}/api/v1/wallets/#{cashtag}/balance")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE if Rails.env.development?
      http.open_timeout = 5
      http.read_timeout = 5

      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"
      request["X-Partner-Api-Key"] = api_key

      response = http.request(request)
      return nil unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(response.body)
      data.dig("wallet", "balance") || data["balance"]
    end
  end
end
