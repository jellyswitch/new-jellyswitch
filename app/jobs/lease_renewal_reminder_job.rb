class LeaseRenewalReminderJob < ApplicationJob
  queue_as :default

  def perform
    Operator.find_each do |operator|
      ActsAsTenant.with_tenant(operator) do
        process_operator(operator)
      end
    rescue => e
      Honeybadger.notify(e)
      Rails.logger.error("LeaseRenewalReminderJob failed for operator #{operator.id}: #{e.message}")
    end
  end

  private

  def process_operator(operator)
    operator.locations.each do |location|
      location.office_leases.active.find_each do |lease|
        next unless within_renewal_window?(lease)

        if lease.auto_renew?
          # Auto-renew leases get a renewal proposal to act on (unchanged).
          next if lease.has_pending_renewal?
          create_renewal_request(lease, operator, location)
        else
          # Fixed-term leases used to lapse silently — nobody was warned. Send a
          # one-time heads-up (operator + lessee) before the end_date passes.
          next if lease.renewal_notice_sent_at.present?
          send_expiry_notice(lease, operator, location)
          lease.update_column(:renewal_notice_sent_at, Time.current)
        end
      rescue => e
        Honeybadger.notify(e)
        Rails.logger.error("LeaseRenewalReminderJob failed for lease #{lease.id}: #{e.message}")
      end
    end
  end

  def within_renewal_window?(lease)
    days_until_end = (lease.end_date - Date.today).to_i
    days_until_end > 0 && days_until_end <= lease.renewal_notice_days
  end

  # A fixed-term (auto_renew:false) lease deliberately isn't set to renew, so it
  # gets a plain expiry heads-up rather than a renewal proposal: an in-app admin
  # feed card + email to the operator, and an email to the lessee.
  def send_expiry_notice(lease, operator, location)
    notify_operator_of_expiry(lease, operator, location)
    notify_lessee_of_expiry(lease, operator, location)
  end

  def notify_operator_of_expiry(lease, operator, location)
    text = "Lease for #{lease.office_name} (#{lease.leasee_name}) ends #{lease.pretty_date} " \
           "and is not set to auto-renew."
    subject_user = lease.individual_lease? ? lease.user : lease.organization&.owner
    if subject_user
      FeedItemCreator.create_feed_item(
        operator, location, subject_user,
        {
          "type" => "lease_expiring",
          "text" => text,
          "body" => text,
          "office_lease_id" => lease.id,
          "user_name" => lease.leasee_name,
        },
      )
    end

    return unless operator.contact_email.present?

    UserMailer.lease_expiring_operator_email(operator, lease, location).deliver_now
  end

  def notify_lessee_of_expiry(lease, operator, location)
    recipient = lease.individual_lease? ? lease.user : lease.organization&.owner
    return unless recipient&.email.present?

    UserMailer.lease_expiring_lessee_email(recipient, operator, lease, location).deliver_now
  end

  def create_renewal_request(lease, operator, location)
    current_price = lease.subscription.plan.amount_in_cents
    proposed_price = lease.calculate_renewal_price

    request = LeaseRenewalRequest.create!(
      office_lease: lease,
      operator: operator,
      location: location,
      current_price_in_cents: current_price,
      proposed_price_in_cents: proposed_price,
      proposed_start_date: lease.end_date,
      proposed_end_date: lease.end_date + 1.year,
      escalation_applied: lease.escalation_description,
      status: "pending_leasee",
      expires_at: lease.end_date - 14.days # must respond 2 weeks before lease end
    )

    send_notification(lease, request, operator, location)
    create_feed_item(lease, request, operator, location)
  end

  def send_notification(lease, request, operator, location)
    recipient = if lease.individual_lease?
      lease.user
    elsif lease.organization&.owner.present?
      lease.organization.owner
    end

    return unless recipient&.email.present?

    UserMailer.lease_renewal_proposal_email(recipient, operator, request, location).deliver_now
  end

  def create_feed_item(lease, request, operator, location)
    user = lease.individual_lease? ? lease.user : lease.organization&.owner
    return unless user

    FeedItemCreator.create_feed_item(
      operator,
      location,
      user,
      {
        text: "Lease renewal proposal sent for #{lease.office.name} — #{request.current_price_formatted} → #{request.proposed_price_formatted} (#{request.escalation_applied}).",
        type: "lease_renewal"
      }
    )
  end
end
