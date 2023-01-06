
class Billing::Payment::SetToOutOfBand
  include Interactor

  delegate :user, to: :context

  def call
    if !user.update(card_added: false, out_of_band: true, bill_to_organization: false)
      context.fail!(message: "An error occurred.")
    end
  end
end
