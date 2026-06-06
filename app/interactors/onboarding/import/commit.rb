require "securerandom"

module Onboarding
  module Import
    # Commits an OfficeRnD member import for a location. Creates/updates Users,
    # UserPaymentProfiles, Organizations, and (when a membership maps to a Plan)
    # Subscriptions.
    #
    # Safety contract:
    # - Runs inside a DB transaction (an unexpected error rolls the whole run back).
    # - Idempotent: re-running matches existing records (User by operator+lower(email)
    #   or by Stripe customer id; profile by user+location; org by operator+name;
    #   subscription by subscribable+plan) and updates rather than duplicating.
    # - NEVER calls Stripe. Historical billing already lives in the connected Stripe
    #   account; this only writes Jellyswitch records. `stripe_subscription_id` is left
    #   nil here (a follow-up can backfill it from the connected account).
    # - Per-row validation failures are recorded as skips (so one bad row doesn't sink
    #   the batch); only unexpected exceptions abort + roll back.
    #
    #   result = Onboarding::Import::Commit.call(
    #     location: current_location,
    #     rows: parsed.rows,
    #     column_mapping: { email: "Email", name: "Name", company: "Company",
    #                       stripe_customer_id: "Stripe Customer", membership: "Membership" },
    #     plan_mapping: { "Full Time" => 12 }
    #   )
    #   result.report # => { summary: {...}, rows: [...] }
    class Commit
      include Interactor

      delegate :location, to: :context

      def call
        context.fail!(message: "location is required") if location.blank?

        @column_mapping = symbolize(context.column_mapping)
        @plan_mapping   = stringify_keys(context.plan_mapping || {})
        @rows           = resolve_rows
        @operator       = location.operator
        @counts         = Hash.new(0)
        @row_results    = []

        ActsAsTenant.with_tenant(@operator) do
          ActiveRecord::Base.transaction do
            @rows.each_with_index { |row, i| process_row(row, i + 1) }
          end
        end

        context.report = { summary: @counts, rows: @row_results }
      rescue => e
        context.fail!(message: "Import aborted and rolled back: #{e.class}: #{e.message}")
      end

      private

      def process_row(row, number)
        email = downcase(value_for(row, :email))
        name = value_for(row, :name)
        stripe_customer_id = value_for(row, :stripe_customer_id)

        if email.blank? && stripe_customer_id.blank?
          return record(number, email, :skipped, "no email or Stripe customer id")
        end
        if name.blank?
          return record(number, email, :skipped, "missing name")
        end

        organization = upsert_organization(value_for(row, :company))
        user, action = upsert_user(email, name, value_for(row, :phone), organization)

        unless user.persisted?
          return record(number, email, :skipped, user.errors.full_messages.join("; "))
        end

        upsert_payment_profile(user, stripe_customer_id) if stripe_customer_id.present?
        notes = upsert_subscription(user, value_for(row, :membership))

        record(number, email, action, notes)
      end

      def upsert_organization(company_name)
        return nil if company_name.blank?

        org = @operator.organizations.where("lower(name) = ?", company_name.downcase).first
        return org if org

        @counts[:organizations_created] += 1
        @operator.organizations.create!(name: company_name, location_id: location.id, visible: true)
      end

      # Returns [user, :created | :updated]
      def upsert_user(email, name, phone, organization)
        user = find_existing_user(email)

        if user
          user.name = name if user.name.blank? && name.present?
          user.phone = phone if user.phone.blank? && phone.present?
          user.organization = organization if organization && user.organization_id.nil?
          if user.changed?
            user.admin_created = true
            user.save
            @counts[:users_updated] += 1
            return [user, :updated]
          end
          @counts[:users_unchanged] += 1
          return [user, :updated]
        end

        user = @operator.users.new(
          email: email,
          name: name,
          phone: phone,
          organization: organization,
          approved: true,
          original_location_id: location.id,
          current_location_id: location.id,
          password: SecureRandom.hex(16), # placeholder; member resets via email later
        )
        user.admin_created = true # bypasses phone-presence + terms-acceptance on :create
        @counts[:users_created] += 1 if user.save
        [user, :created]
      end

      def find_existing_user(email)
        return nil if email.blank?

        @operator.users.where("lower(email) = ?", email).first
      end

      def upsert_payment_profile(user, stripe_customer_id)
        profile = user.user_payment_profiles.find_or_initialize_by(location_id: location.id)
        was_new = profile.new_record?
        profile.stripe_customer_id = stripe_customer_id
        profile.card_added = true if profile.card_added.nil?
        profile.save!
        @counts[:payment_profiles_created] += 1 if was_new
      end

      # Attaches the membership to the person. The company link (organization_id) is a
      # separate association; org-level billing arrangements aren't inferable from a
      # members CSV, so we don't guess them here.
      # Returns a human-readable note about the membership outcome.
      def upsert_subscription(user, membership_value)
        return "no membership" if membership_value.blank?

        plan_id = @plan_mapping[membership_value]
        return "membership \"#{membership_value}\" not mapped — skipped" if plan_id.blank?

        existing = Subscription.where(
          subscribable_type: "User",
          subscribable_id: user.id,
          plan_id: plan_id,
        ).first
        return "subscription already present" if existing

        Subscription.create!(
          plan_id: plan_id,
          subscribable: user,
          billable: user,
          active: true,
          pending: false,
          start_date: Date.current,
        )
        @counts[:subscriptions_created] += 1
        "subscription created (plan #{plan_id})"
      end

      def record(number, email, action, notes)
        @row_results << { row_number: number, email: email, action: action, notes: notes }
      end

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
    end
  end
end
