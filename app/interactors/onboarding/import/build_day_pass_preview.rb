module Onboarding
  module Import
    # DRY RUN for the historical day-pass backfill. Resolves each row's user, maps the
    # day-pass-type value to an existing DayPassType, parses the date — all read-only.
    #
    #   result = Onboarding::Import::BuildDayPassPreview.call(
    #     location: current_location, rows: parsed.rows,
    #     column_mapping: { email: "Email", day_pass_type: "Pass Type", day: "Date", complimentary: "Comp" },
    #     type_mapping: { "Day Pass" => 7 } # day-pass-type value => DayPassType id
    #   )
    class BuildDayPassPreview
      include Interactor
      include Officernd::ImportRowHelpers

      delegate :location, to: :context

      def call
        context.fail!(message: "location is required") if location.blank?

        @column_mapping = symbolize(context.column_mapping)
        @type_mapping   = stringify_keys(context.type_mapping || {})
        @rows           = resolve_rows
        @operator       = location.operator

        ActsAsTenant.with_tenant(@operator) do
          context.preview = build
        end
      end

      private

      def build
        rows = @rows.each_with_index.map { |row, i| analyze_row(row, i + 1) }

        {
          total_rows: rows.length,
          summary: summarize(rows),
          rows: rows,
          type_values: type_summary(rows),
        }
      end

      def analyze_row(row, number)
        email = downcase(value_for(row, :email))
        type_value = value_for(row, :day_pass_type)
        user = resolve_user(value_for(row, :stripe_customer_id), email)
        day = parse_date(value_for(row, :day))
        mapped_type_id = type_value.present? ? @type_mapping[type_value] : nil

        warnings = []
        error = nil

        error ||= "user not found" if user.nil?
        error ||= "missing/invalid date" if day.nil?
        if type_value.present? && mapped_type_id.blank?
          error ||= "day-pass type \"#{type_value}\" not mapped"
        elsif type_value.blank?
          error ||= "no day-pass type"
        end

        exists = error ? false : existing_day_pass?(user, day, mapped_type_id)

        {
          row_number: number,
          email: email,
          user_id: user&.id,
          day_pass_type: type_value,
          mapped_type_id: mapped_type_id,
          day: day&.iso8601,
          complimentary: parse_bool(value_for(row, :complimentary)),
          exists: exists,
          warnings: warnings,
          error: error,
        }
      end

      def existing_day_pass?(user, day, type_id)
        return false if user.nil? || day.nil? || type_id.blank?

        DayPass.exists?(user_id: user.id, day: day, day_pass_type_id: type_id)
      end

      def summarize(rows)
        creatable = rows.select { |r| r[:error].blank? }
        {
          new: creatable.count { |r| !r[:exists] },
          existing: creatable.count { |r| r[:exists] },
          errors: rows.count { |r| r[:error].present? },
          warnings: rows.count { |r| r[:warnings].present? },
        }
      end

      def type_summary(rows)
        rows.reject { |r| r[:day_pass_type].blank? }
          .group_by { |r| r[:day_pass_type] }
          .map { |value, group| { value: value, count: group.length, mapped: @type_mapping[value].present? } }
          .sort_by { |t| -t[:count] }
      end
    end
  end
end
