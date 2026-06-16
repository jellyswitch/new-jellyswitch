class Billing::DayPassBundles::CheckInGuest
  include Interactor

  def call
    redemption = context.bundle.burn!(
      kind: :guest,
      performed_by: context.performed_by,
      guest_name: context.guest_name,
    )
    context.redemption = redemption
  rescue DayPassBundle::NoPassesRemaining
    context.fail!(message: "No passes remaining in this bundle.")
  end
end
