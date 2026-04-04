class MailchimpSyncJob < ApplicationJob
  queue_as :default

  def perform(user_id = nil)
    if user_id
      sync_single_user(User.find(user_id))
    else
      sync_all
    end
  end

  private

  def sync_all
    Operator.where(billing_state: "production").find_each do |operator|
      next unless operator.mailchimp_api_key.present? && operator.mailchimp_audience_id.present?

      ActsAsTenant.with_tenant(operator) do
        operator.locations.each do |location|
          next unless location.visible?

          users = User.for_space(operator).originally_at_location(location).visible
          users.find_each do |user|
            upsert_to_mailchimp(user, operator)
          rescue => e
            Rails.logger.warn("Mailchimp sync failed for user #{user.id}: #{e.message}")
          end
        end
      end
    end
  end

  def sync_single_user(user)
    operator = user.operator
    return unless operator.mailchimp_api_key.present? && operator.mailchimp_audience_id.present?

    ActsAsTenant.with_tenant(operator) do
      upsert_to_mailchimp(user, operator)
    end
  end

  def upsert_to_mailchimp(user, operator)
    gibbon = Gibbon::Request.new(api_key: operator.mailchimp_api_key)
    subscriber_hash = Digest::MD5.hexdigest(user.email.downcase)

    merge_fields = {
      FNAME: user.name.to_s.split.first,
      LNAME: user.name.to_s.split[1..].join(" "),
      LOCATION: user.original_location&.name,
    }

    # Build plan name
    active_sub = user.subscriptions.active.first
    merge_fields[:PLAN] = active_sub&.plan&.name || ""

    gibbon.lists(operator.mailchimp_audience_id)
      .members(subscriber_hash)
      .upsert(
        body: {
          email_address: user.email,
          status_if_new: "subscribed",
          merge_fields: merge_fields,
          tags: build_tags(user)
        }
      )
  end

  def build_tags(user)
    tags = []
    tags << "member" if user.subscriptions.active.any?
    tags << "day_pass" if user.day_passes.any?
    tags << "room_booker" if user.reservations.any?
    tags << "pending" if !user.approved?
    tags << "inactive" if user.last_active_at.present? && user.last_active_at < 30.days.ago
    tags << "opted_out" if user.email_opted_out?
    tags
  end
end
