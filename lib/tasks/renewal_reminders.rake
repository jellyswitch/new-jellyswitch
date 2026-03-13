namespace :reminders do
  desc "Send membership renewal reminder emails (run daily via Heroku Scheduler)"
  task send_renewal_reminders: :environment do
    SendRenewalRemindersJob.perform_now
  end
end
