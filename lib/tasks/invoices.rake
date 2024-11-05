task backfill_invoices: :environment do
  Location.all.each do |location|
    BackfillInvoices.call(location: location)
  end
end