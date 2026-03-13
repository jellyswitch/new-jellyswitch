class SendRenewalRemindersJob < ApplicationJob
  queue_as :default

  def perform
    Operator.find_each do |operator|
      ActsAsTenant.with_tenant(operator) do
        reminder_days = operator.renewal_reminder_days || 7
        next if reminder_days <= 0

        target_date = reminder_days.days.from_now.to_date

        Subscription.where(active: true).find_each do |subscription|
          next unless subscription.has_stripe_subscription?

          begin
            period_end = subscription.current_period_end
            next unless period_end.to_date == target_date

            user = subscription.subscribable
            next unless user.is_a?(User)

            # Duplicate check: don't send if already sent for this period
            cache_key = "renewal_reminder:#{subscription.id}:#{period_end.to_date}"
            next if Rails.cache.exist?(cache_key)

            UserMailer.renewal_reminder_email(user, operator, subscription).deliver_now
            Rails.cache.write(cache_key, true, expires_in: (reminder_days + 1).days)
          rescue => e
            Honeybadger.notify(e)
            Rails.logger.error("SendRenewalRemindersJob error for subscription #{subscription.id}: #{e.class}: #{e.message}")
          end
        end
      end
    end
  end
end
