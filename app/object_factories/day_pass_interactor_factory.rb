class DayPassInteractorFactory
  def self.for(token, operator)
    if token.present?
      if operator.checkin_required?
        Billing::DayPasses::UpdatePaymentAndCreateDayPassAndCheckin
      else
        Billing::DayPasses::UpdatePaymentAndCreateDayPass
      end
    else
      if operator.checkin_required?
        Billing::DayPasses::CreateDayPassAndCheckin
      else
        Billing::DayPasses::CreateDayPass
      end
    end
  end
end