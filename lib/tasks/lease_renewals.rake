namespace :leases do
  desc "Check for upcoming lease renewals and send proposals"
  task send_renewal_reminders: :environment do
    LeaseRenewalReminderJob.perform_now
  end

  desc "Fetch latest CPI data from BLS"
  task fetch_cpi: :environment do
    CpiFetchJob.perform_now
  end
end
