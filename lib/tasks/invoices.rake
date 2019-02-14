task backfill_invoices: :environment do
  BackfillInvoices.call
end