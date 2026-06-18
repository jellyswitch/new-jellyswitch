namespace :day_pass_bundles do
  # Enqueue the onboarding "directions" email for existing active bundle holders.
  # Configure + ENABLE the onboarding template first — this is a no-op otherwise.
  #
  #   heroku run rake day_pass_bundles:backfill_onboarding --app jellyswitch-production
  #   heroku run rake "day_pass_bundles:backfill_onboarding[279]" --app jellyswitch-production
  #
  # Only enqueues a background job (Redis), so it works even when one-off dynos
  # can't reach Postgres; the job itself runs on a worker.
  desc "Enqueue onboarding emails for existing active Day Pass Bundle holders (optional [operator_id])"
  task :backfill_onboarding, [:operator_id] => :environment do |_t, args|
    operator_id = args[:operator_id].presence
    DayPassBundleOnboardingBackfillJob.perform_later(operator_id: operator_id)
    puts "Enqueued DayPassBundleOnboardingBackfillJob (operator_id=#{operator_id || 'ALL'})."
  end
end
