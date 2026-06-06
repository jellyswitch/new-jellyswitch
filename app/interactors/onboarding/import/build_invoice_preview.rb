module Onboarding
  module Import
    # DRY RUN for the historical-invoice backfill. Resolves each row's billable, parses
    # amounts, normalizes the status, and checks whether the invoice already exists —
    # all read-only. No writes, no Stripe calls.
    #
    #   result = Onboarding::Import::BuildInvoicePreview.call(
    #     location: current_location,
    #     rows: parsed.rows,
    #     column_mapping: { stripe_invoice_id: "Stripe Invoice", stripe_customer_id: "Stripe Customer",
    #                       email: "Email", number: "Invoice #", amount_due: "Amount Due",
    #                       amount_paid: "Amount Paid", status: "Status", date: "Date", due_date: "Due Date" },
    #     amount_format: :dollars # or :cents
    #   )
    #   result.preview
    class BuildInvoicePreview
      include Interactor
      include Officernd::ImportRowHelpers

      delegate :location, to: :context

      def call
        context.fail!(message: "location is required") if location.blank?

        @column_mapping = symbolize(context.column_mapping)
        @rows           = resolve_rows
        @operator       = location.operator
        @amount_format  = (context.amount_format || :dollars).to_sym

        ActsAsTenant.with_tenant(@operator) do
          context.preview = build
        end
      end

      private

      def build
        rows = @rows.each_with_index.map { |row, i| analyze_row(row, i + 1) }

        {
          total_rows: rows.length,
          amount_format: @amount_format,
          summary: summarize(rows),
          rows: rows,
        }
      end

      def analyze_row(row, number)
        stripe_invoice_id = value_for(row, :stripe_invoice_id)
        invoice_number = value_for(row, :number)
        billable, match = resolve_billable(value_for(row, :stripe_customer_id), downcase(value_for(row, :email)))

        warnings = []
        error = nil

        amount_due_cents, due_err = parse_money(value_for(row, :amount_due))
        amount_paid_cents, paid_err = parse_money(value_for(row, :amount_paid))
        error ||= "amount_due: #{due_err}" if due_err
        error ||= "amount_paid: #{paid_err}" if paid_err

        raw_status = value_for(row, :status)
        status = Officernd::InvoiceStatus.normalize(raw_status)
        if raw_status.present? && status.nil?
          warnings << "unrecognized status \"#{raw_status}\" — will default to \"open\""
        end

        if billable.nil?
          error ||= "billable not found (no matching member/organization)"
        end
        if stripe_invoice_id.blank? && invoice_number.blank?
          warnings << "no Stripe invoice id or number — weak idempotency key"
        end

        exists = error ? false : existing_invoice?(stripe_invoice_id, invoice_number, billable)

        {
          row_number: number,
          stripe_invoice_id: stripe_invoice_id,
          number: invoice_number,
          billable_match: match,
          billable_type: billable&.class&.name,
          billable_id: billable&.id,
          amount_due_cents: amount_due_cents,
          amount_paid_cents: amount_paid_cents,
          status: status || (raw_status.present? ? Officernd::InvoiceStatus::DEFAULT : nil),
          raw_status: raw_status,
          exists: exists,
          warnings: warnings,
          error: error,
        }
      end

      def summarize(rows)
        creatable = rows.select { |r| r[:error].blank? }
        {
          new: creatable.count { |r| !r[:exists] },
          existing: creatable.count { |r| r[:exists] },
          errors: rows.count { |r| r[:error].present? },
          warnings: rows.count { |r| r[:warnings].present? },
          total_amount_due_cents: creatable.sum { |r| r[:amount_due_cents].to_i },
          total_amount_paid_cents: creatable.sum { |r| r[:amount_paid_cents].to_i },
        }
      end
    end
  end
end
