module Officernd
  # Shared instance helpers for the invoice import interactors. Expects the including
  # interactor to set @column_mapping, @rows, @operator, and (for money) @amount_format,
  # and to respond to `context`/`location`.
  module ImportRowHelpers
    def resolve_rows
      return context.rows if context.rows.present?
      return context.parsed.rows if context.parsed.respond_to?(:rows)

      []
    end

    def value_for(row, field)
      header = @column_mapping[field]
      return nil if header.blank?

      raw = row[header] || row[header.to_s]
      raw.is_a?(String) ? raw.strip.presence : raw
    end

    def downcase(value)
      value.is_a?(String) ? value.downcase.presence : value
    end

    def symbolize(hash)
      (hash || {}).each_with_object({}) { |(k, v), acc| acc[k.to_sym] = v }
    end

    def stringify_keys(hash)
      (hash || {}).each_with_object({}) { |(k, v), acc| acc[k.to_s] = v }
    end

    # Returns [cents_or_nil, error_message_or_nil]
    def parse_money(raw)
      [Officernd::Money.to_cents(raw, format: @amount_format || :dollars), nil]
    rescue Officernd::Money::ParseError => e
      [nil, e.message]
    end

    # Returns [billable_record_or_nil, :user | :organization | :none]
    def resolve_billable(stripe_customer_id, email)
      if stripe_customer_id.present?
        user = User.find_by_stripe_customer_id(stripe_customer_id)
        return [user, :user] if user

        org = Organization.find_by(stripe_customer_id: stripe_customer_id)
        return [org, :organization] if org
      end

      if email.present?
        user = @operator.users.where("lower(email) = ?", email).first
        return [user, :user] if user
      end

      [nil, :none]
    end

    def existing_invoice(stripe_invoice_id, number, billable)
      return Invoice.find_by(stripe_invoice_id: stripe_invoice_id) if stripe_invoice_id.present?
      return nil if number.blank? || billable.nil?

      Invoice.find_by(number: number, billable_type: billable.class.name, billable_id: billable.id)
    end

    def existing_invoice?(stripe_invoice_id, number, billable)
      existing_invoice(stripe_invoice_id, number, billable).present?
    end

    # Resolve a User (day passes belong to a person, not an organization).
    def resolve_user(stripe_customer_id, email)
      if stripe_customer_id.present?
        user = User.find_by_stripe_customer_id(stripe_customer_id)
        return user if user
      end
      return nil if email.blank?

      @operator.users.where("lower(email) = ?", email).first
    end

    TRUTHY = %w[true yes y 1 t comp complimentary free].freeze

    def parse_bool(value)
      return false if value.blank?

      TRUTHY.include?(value.to_s.strip.downcase)
    end

    def parse_date(value)
      return nil if value.blank?

      Date.parse(value.to_s)
    rescue ArgumentError
      nil
    end
  end
end
