require 'shellwords'

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

# rake test_apns
task test_apns: :environment do
  apn = Houston::Client.production

  operator_id = 243 # untethered by default
  operator = Operator.find(operator_id)
  
  apn.certificate = operator.push_notification_certificate.download
  
  admin_users = User.admins.for_space(operator)
  for tester in admin_users
    break unless tester.ios_token?
    notification = Houston::Notification.new(device: tester.ios_token)
    notification.alert = 'This is a push notification test. This is only a test...'
    notification.badge = 57
    apn.push(notification)
  end
end

task reindex_models: :environment do
  [Announcement, Room, Door, Location, Organization, FeedItem, User].map {|klass| klass.reindex }
end