module Onboarding
  module Import
    # DRY RUN. Analyzes parsed OfficeRnD rows against the current location and produces a
    # structured preview of what an import *would* do. Performs only read-only queries —
    # it never writes records and never calls Stripe.
    #
    #   result = Onboarding::Import::BuildPreview.call(
    #     location:       current_location,
    #     rows:           parsed.rows,                       # array of { header => value }
    #     column_mapping: { email: "Email", name: "Name", stripe_customer_id: "Stripe Customer" },
    #     plan_mapping:   { "Full Time" => 12, "Part Time" => 13 } # membership value => Plan id (optional)
    #   )
    #   result.preview # => structured Hash (see #build)
    #
    # Match priority per row: Stripe Customer ID (UserPaymentProfile @ this location) →
    # email (lowercased, scoped to the operator) → treated as a new member.
    class BuildPreview
      include Interactor

      delegate :location, to: :context

      def call
        context.fail!(message: "location is required") if location.blank?

        @column_mapping = symbolize(context.column_mapping)
        @plan_mapping   = stringify_keys(context.plan_mapping || {})
        @rows           = resolve_rows

        context.preview = build
      end

      private

      def resolve_rows
        return context.rows if context.rows.present?
        return context.parsed.rows if context.parsed.respond_to?(:rows)

        []
      end

      def build
        seen_emails = Hash.new(0)
        analyzed = @rows.each_with_index.map do |row, index|
          analyze_row(row, index + 1, seen_emails)
        end

        {
          total_rows: analyzed.length,
          summary: summarize(analyzed),
          rows: analyzed,
          membership_values: membership_summary(analyzed),
          unmatched: analyzed.select { |r| r[:error].present? || r[:match_type] == :new },
        }
      end

      def analyze_row(row, number, seen_emails)
        email = downcase(value_for(row, :email))
        name = value_for(row, :name)
        stripe_customer_id = value_for(row, :stripe_customer_id)
        membership = value_for(row, :membership)

        warnings = []
        warnings << "missing name" if name.blank?
        if email.present?
          seen_emails[email] += 1
          warnings << "duplicate email in file" if seen_emails[email] > 1
        end

        match_type, matched_user = match(email, stripe_customer_id)

        mapped_plan_id = membership.present? ? @plan_mapping[membership] : nil
        if membership.present? && mapped_plan_id.nil?
          warnings << "membership \"#{membership}\" not mapped to a plan"
        end

        error = nil
        error = "no email or Stripe customer id — cannot identify member" if email.blank? && stripe_customer_id.blank?

        {
          row_number: number,
          email: email,
          name: name,
          phone: value_for(row, :phone),
          company: value_for(row, :company),
          stripe_customer_id: stripe_customer_id,
          membership: membership,
          match_type: match_type,
          matched_user_id: matched_user&.id,
          mapped_plan_id: mapped_plan_id,
          warnings: warnings,
          error: error,
        }
      end

      # Returns [match_type, user_or_nil]
      def match(email, stripe_customer_id)
        if stripe_customer_id.present?
          profile = UserPaymentProfile.find_by(location_id: location.id, stripe_customer_id: stripe_customer_id)
          return [:existing_stripe, profile.user] if profile&.user
        end

        if email.present?
          user = location.operator.users.where("lower(email) = ?", email).first
          return [:existing_email, user] if user
        end

        [:new, nil]
      end

      def summarize(rows)
        {
          new: rows.count { |r| r[:match_type] == :new && r[:error].blank? },
          matched_existing: rows.count { |r| %i[existing_stripe existing_email].include?(r[:match_type]) },
          errors: rows.count { |r| r[:error].present? },
          warnings: rows.count { |r| r[:warnings].present? },
        }
      end

      def membership_summary(rows)
        rows.reject { |r| r[:membership].blank? }
          .group_by { |r| r[:membership] }
          .map do |value, group|
            plan_id = @plan_mapping[value]
            {
              value: value,
              count: group.length,
              mapped_plan_id: plan_id,
              mapped: plan_id.present?,
            }
          end
          .sort_by { |m| -m[:count] }
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
    end
  end
end
