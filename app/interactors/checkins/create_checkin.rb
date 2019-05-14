class Checkins::CreateCheckin
  include Interactor

  delegate :user, :location, :operator, to: :context

  def call
    if location.operator != operator
      context.fail!(message: "Cannot check into #{location.name} for operator #{operator.name}")
    end

    context.checkin = Checkin.create!(
      user: user,
      location: location,
      datetime_in: Time.current,
      invoice_id: nil
    )
  end

  def rollback
    context.checkin.destroy
  end
end