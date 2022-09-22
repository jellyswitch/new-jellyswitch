# typed: true
class ScrubUserData
  include Interactor

  def call
    user = context.user

    unique_id = SecureRandom.uuid.slice(1, 7)

    user.name = "DeletedUser" + unique_id
    user.email = "deleted_user" + unique_id + "@jellyswitch.com"
    user.slug = ""
    user.bio = ""
    user.linkedin = ""
    user.twitter = ""
    user.website = ""
    user.phone = ""
    user.stripe_customer_id = ""
    user.card_added = false
    user.archived = true
    user.organization_id = nil
    user.profile_photo.detach

    if !user.save
      context.fail!(message: "Unable to scrub user.")
    end
  end
end