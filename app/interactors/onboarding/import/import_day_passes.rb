module Onboarding
  module Import
    # Backfills historical day passes from an OfficeRnD export as DayPass records.
    #
    # Safety contract:
    # - DB transaction; an unexpected error rolls the whole run back.
    # - Idempotent: matches existing day passes by (user, day, day_pass_type) and skips.
    # - Sets `imported: true` so the model SKIPS its member-lifecycle side effects
    #   (welcome-drip enrollment + activity-feed entries) that must not fire for
    #   back-dated records.
    # - NEVER calls Stripe.
    # - Rows with no resolvable user, no valid date, or an unmapped day-pass type are
    #   recorded as skips; only unexpected errors abort.
    #
    #   result = Onboarding::Import::ImportDayPasses.call(
    #     location: current_location, rows: parsed.rows,
    #     column_mapping: {...}, type_mapping: { "Day Pass" => 7 }
    #   )
    class ImportDayPasses
      include Interactor
      include Officernd::ImportRowHelpers

      delegate :location, to: :context

      def call
        context.fail!(message: "location is required") if location.blank?

        @column_mapping = symbolize(context.column_mapping)
        @type_mapping   = stringify_keys(context.type_mapping || {})
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
        context.fail!(message: "Day-pass import aborted and rolled back: #{e.class}: #{e.message}")
      end

      private

      def process_row(row, number)
        user = resolve_user(value_for(row, :stripe_customer_id), downcase(value_for(row, :email)))
        return record(number, :skipped, "user not found") if user.nil?

        day = parse_date(value_for(row, :day))
        return record(number, :skipped, "missing/invalid date") if day.nil?

        type_value = value_for(row, :day_pass_type)
        type_id = type_value.present? ? @type_mapping[type_value] : nil
        return record(number, :skipped, "day-pass type \"#{type_value}\" not mapped") if type_id.blank?

        if DayPass.exists?(user_id: user.id, day: day, day_pass_type_id: type_id)
          return record(number, :skipped, "already imported")
        end

        DayPass.create!(
          user: user,
          billable: user,
          day_pass_type_id: type_id,
          day: day,
          operator_id: @operator.id,
          location_id: location.id,
          complimentary: parse_bool(value_for(row, :complimentary)),
          stripe_charge_id: value_for(row, :stripe_charge_id),
          imported: true, # skip welcome-drip + activity-feed side effects
        )

        @counts[:day_passes_created] += 1
        record(number, :created, "#{day} (type #{type_id})")
      end

      def record(number, action, notes)
        @counts[:skipped] += 1 if action == :skipped
        @row_results << { row_number: number, action: action, notes: notes }
      end
    end
  end
end
