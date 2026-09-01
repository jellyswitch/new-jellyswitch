namespace :payment_cutoff do
  desc "Advance the non-payment email drip and suspend still-unpaid members (nightly)"
  task run: :environment do
    PaymentCutoffJob.perform_now
  end
end
