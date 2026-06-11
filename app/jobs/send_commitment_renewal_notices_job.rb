class SendCommitmentRenewalNoticesJob < ApplicationJob
  queue_as :default

  # Notifies committed members `commitment_notice_days` (default 30) before their
  # commitment term re-arms — their opt-out window (see ADR 0005). Distinct from
  # SendRenewalRemindersJob (the 7-day routine billing reminder). Stripe-
  # independent: the term boundary is derived locally from start_date.
  def perform
    Operator.find_each do |operator|
      ActsAsTenant.with_tenant(operator) do
        notice_days = operator.commitment_notice_days || 30
        next if notice_days <= 0
        target_date = notice_days.days.from_now.to_date

        Subscription.joins(:plan)
                    .where(plans: { operator_id: operator.id }, active: true)
                    .find_each do |subscription|
          begin
            next unless subscription.subscribable.is_a?(User)
            next unless subscription.plan&.has_commitment_interval?
            next if subscription.cancelling_at_end_of_billing_period? # already opting out

            boundary = subscription.commitment_term_end
            next unless boundary&.to_date == target_date

            cache_key = "commitment_notice:#{subscription.id}:#{boundary.to_date}"
            next if Rails.cache.exist?(cache_key)

            UserMailer.commitment_renewal_email(
              subscription.subscribable, operator, subscription, subscription.plan.location
            ).deliver_now
            Rails.cache.write(cache_key, true, expires_in: (notice_days + 1).days)
          rescue => e
            Honeybadger.notify(e)
            Rails.logger.error("SendCommitmentRenewalNoticesJob error for subscription #{subscription.id}: #{e.class}: #{e.message}")
          end
        end
      end
    end
  end
end
