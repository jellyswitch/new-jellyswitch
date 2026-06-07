module Onboarding
  module Import
    # Backfills historical invoices from an OfficeRnD export as Jellyswitch Invoice
    # records, anchored to their existing Stripe ids.
    #
    # Safety contract:
    # - DB transaction; an unexpected error rolls the whole run back.
    # - Idempotent: matches existing invoices by stripe_invoice_id (or number+billable)
    #   and updates rather than duplicating.
    # - NEVER calls Stripe, and — unlike the live CreateInvoice path — does NOT run
    #   Billing::Invoices::AddCreditsToSubscribable, so historical invoices don't grant
    #   retroactive credits.
    # - Rows whose billable can't be resolved, or whose amounts won't parse, are recorded
    #   as skips; only unexpected errors abort.
    # - Preserves the original invoice date and back-dates created_at to match.
    #
    #   result = Onboarding::Import::ImportInvoices.call(
    #     location: current_location, rows: parsed.rows,
    #     column_mapping: {...}, amount_format: :dollars
    #   )
    #   result.report # => { summary: {...}, rows: [...] }
    class ImportInvoices
      include Interactor
      include Officernd::ImportRowHelpers

      delegate :location, to: :context

      def call
        context.fail!(message: "location is required") if location.blank?

        @column_mapping = symbolize(context.column_mapping)
        @rows           = resolve_rows
        @operator       = location.operator
        @amount_format  = (context.amount_format || :dollars).to_sym
        @counts         = Hash.new(0)
        @row_results    = []

        ActsAsTenant.with_tenant(@operator) do
          ActiveRecord::Base.transaction do
            @rows.each_with_index { |row, i| process_row(row, i + 1) }
          end
        end

        context.report = { summary: @counts, rows: @row_results }
      rescue => e
        context.fail!(message: "Invoice import aborted and rolled back: #{e.class}: #{e.message}")
      end

      private

      def process_row(row, number)
        stripe_invoice_id = value_for(row, :stripe_invoice_id)
        invoice_number = value_for(row, :number)
        billable, = resolve_billable(value_for(row, :stripe_customer_id), downcase(value_for(row, :email)))

        return record(number, stripe_invoice_id, :skipped, "billable not found") if billable.nil?

        amount_due_cents, due_err = parse_money(value_for(row, :amount_due))
        amount_paid_cents, paid_err = parse_money(value_for(row, :amount_paid))
        return record(number, stripe_invoice_id, :skipped, "amount_due: #{due_err}") if due_err
        return record(number, stripe_invoice_id, :skipped, "amount_paid: #{paid_err}") if paid_err

        invoice = existing_invoice(stripe_invoice_id, invoice_number, billable)
        action = invoice ? :updated : :created
        invoice ||= Invoice.new

        assign_attributes(invoice, row, billable, stripe_invoice_id, invoice_number, amount_due_cents, amount_paid_cents)
        invoice.save!

        @counts[action == :created ? :invoices_created : :invoices_updated] += 1
        record(number, stripe_invoice_id, action, "#{invoice.status} #{format_cents(invoice.amount_due)}")
      end

      def assign_attributes(invoice, row, billable, stripe_invoice_id, invoice_number, amount_due_cents, amount_paid_cents)
        date = parse_time(value_for(row, :date))
        raw_status = value_for(row, :status)
        status = Officernd::InvoiceStatus.normalize(raw_status) || Officernd::InvoiceStatus::DEFAULT

        invoice.billable = billable
        invoice.operator_id = @operator.id
        invoice.location_id = location.id
        invoice.stripe_invoice_id = stripe_invoice_id if stripe_invoice_id.present?
        invoice.stripe_payment_intent_id = value_for(row, :stripe_payment_intent_id) if value_for(row, :stripe_payment_intent_id).present?
        invoice.number = invoice_number if invoice_number.present?
        invoice.amount_due = amount_due_cents
        invoice.amount_paid = amount_paid_cents
        invoice.status = status
        invoice.description = value_for(row, :description) if value_for(row, :description).present?
        invoice.date = date if date
        invoice.due_date = parse_time(value_for(row, :due_date))

        if invoice.new_record? && date
          invoice.created_at = date
          invoice.updated_at = date
        end
      end

      def parse_time(value)
        return nil if value.blank?

        Time.zone.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def format_cents(cents)
        return "" if cents.nil?

        format("$%.2f", cents / 100.0)
      end

      def record(number, stripe_invoice_id, action, notes)
        @counts[:skipped] += 1 if action == :skipped
        @row_results << { row_number: number, stripe_invoice_id: stripe_invoice_id, action: action, notes: notes }
      end
    end
  end
end
