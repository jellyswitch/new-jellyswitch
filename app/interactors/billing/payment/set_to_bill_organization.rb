
class Billing::Payment::SetToBillOrganization
  include Interactor

  delegate :user, to: :context

  def call
    if user.member_of_organization?
      if user.organization.has_billing_for_location?(user.organization.location)
        user.assign_attributes(bill_to_organization: true, out_of_band: false)
        if !user.save(context: :payment_method)
          context.fail!(message: "Unable to update payment method: #{user.errors.full_messages.join(', ')}")
        end
      else
        context.fail!(message: "Group #{user.organization.name} has no billing info on file.")
      end
    else
      context.fail!(message: "User is not a member of a group.")
    end
  end
end