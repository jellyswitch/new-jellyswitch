class UserManager
  attr_reader :user

  def initialize(user:)
    @user = user
  end

  def ready
    raise GroupOwnerException if user.organization_owner?
    
    ActiveRecord::Base.transaction do
      create_feed_item

      user.update(
        name: name,
        email: email,
        bio: nil,
        linkedin: nil,
        twitter: nil,
        website: nil,
        phone: nil,
        stripe_customer_id: nil,
        archived: true,
        card_added: false,
        organization_id: nil,
        slug: "deleted-user-#{unique_id}",
      )

      user.profile_photo.detach

      user.reservations.future.map do |reservation|
        reservation.update(cancelled: true)
      end

      cancel_subscriptions!
    end
  end

  def cancel_subscriptions!
    failed_results = user.subscriptions.active.map do |subscription|
      Billing::Subscription::CancelStripeSubscription.call(subscription: subscription)
    end.select { |result| !result.success? }

    if failed_results.count.positive?
      raise "Error cancelling subscriptions: #{ failed_results.map(&:message).to_sentence }"
    end
  end

  def create_feed_item
    FeedItems::Create.call(
      blob: { text: "#{user.name} deleted their account.", type: "account_deletion" },
      user: user.operator.users.admins.first,
      operator: user.operator,
      photos: nil
    )
  end

  def name
    "DeletedUser #{unique_id}"
  end

  def email
    "deleted-user-#{unique_id}@jellyswitch.com"
  end

  def unique_id
    @unique_id ||= SecureRandom.uuid.slice(1, 7)
  end
end