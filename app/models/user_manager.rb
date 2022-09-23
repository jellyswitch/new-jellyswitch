class UserManager
  attr_reader :user

  def initialize(user:)
    @user = user
  end

  def ready
    @user.update(
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