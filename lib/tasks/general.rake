task backfill_stripe_credentials: :environment do
  Operator.where(stripe_user_id: nil).each do |op|
    op.update(
      stripe_user_id: ENV['STRIPE_ACCOUNT_ID'],
      stripe_access_token: "bogus",
      stripe_refresh_token: "bogus",
      stripe_publishable_key: "bogus"
    )
  end
end

task checkout_job: :environment do
  CheckoutJob.perform_later
end

task weekly_updates: :environment do
  case (day = Time.current.wday)
  when 1
    WeeklyUpdateJob.perform_later
    Rollbar.info("rake weekly_updates performed", performed: true)
  when 2..7
    Rollbar.info("rake weekly_updates", performed: false, wday: day)
  else
    Rollbar.error("rake weekly_updates wday invalid", performed: false, wday: day)
  end
end

task clean_demo: :environment do
  result = Demo::Clean.call(subdomain: 'southlakecoworking')

  if result.success?
    puts "Success!"
  else
    puts result.message
  end
end
