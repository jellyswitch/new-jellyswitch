namespace :notes do
  desc "Copy every LeadNote into a polymorphic Note row. Idempotent. Activity rows are not re-written."
  task backfill_from_lead_notes: :environment do
    puts "Copying LeadNote rows into Note rows..."
    result = Notes::BackfillFromLeadNotes.call
    puts "Done. created=#{result[:created]} skipped=#{result[:skipped]}"
  end
end
