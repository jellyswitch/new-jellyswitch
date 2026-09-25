class DayPassable::OutOfBand < DayPassable::DefaultDayPass
  # auto_advance: true — ChargeDayPassInvoice skips out-of-band billables, so
  # nothing else finalizes the invoice. Without it (inherited false since the
  # 4/26 synchronous-charge change) the invoice sat in Stripe draft forever and
  # the member was never sent it.
  def invoice_args
    super.merge!(
      auto_advance: true,
      billing: 'send_invoice',
      days_until_due: 30
    )
  end
end
