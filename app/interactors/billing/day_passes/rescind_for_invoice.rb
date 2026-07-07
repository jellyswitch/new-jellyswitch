# Rescinds (destroys) the day pass(es) tied to a refunded / voided invoice so a
# refunded pass no longer grants building access or blocks bundle redemption.
#
# WHY DESTROY, not a "voided" flag: access and every bundle-redeem dedupe guard
# key on the mere EXISTENCE of a day_passes row for a day (has_active_day_pass?,
# the door-unlock gate, ConsumeOnEntry Guard 4, RedeemBundlePass#covered_for_day?,
# CoverageState#already_covered?) — none read a status column. Removing the row is
# the only revoke that can't be missed. Financial history is preserved by the
# Invoice (status: refunded/void), the refunds row, and the refund feed item.
#
# Scope:
#   * Purchased passes link 1:1 to a dedicated invoice via DayPass#invoice_id
#     (Billing::DayPasses::CreateStripeInvoice), so DayPass.where(invoice_id:)
#     finds exactly the pass(es) to rescind. (stripe_charge_id is only set on
#     historical imports, so it is NOT used.)
#   * Only today-or-future passes are removed — a genuinely-past pass is left as
#     usage history (it grants no access anyway).
#   * A pass still backing an ACTIVE (non-cancelled) reservation is left alone, so
#     a refund never collaterally uncovers a live booking; those unwind through
#     the reservation-cancel flow instead.
#   * Bundle-minted entry passes have invoice_id nil, and bundle-product refunds
#     link to the DayPassBundle — so neither is matched here.
class Billing::DayPasses::RescindForInvoice
  include Interactor

  delegate :invoice, to: :context

  def call
    return if invoice.nil?

    ActsAsTenant.with_tenant(invoice.operator) do
      DayPass.where(invoice_id: invoice.id).find_each do |day_pass|
        next if day_pass.day < today_for(day_pass)
        next if day_pass.reservation.present? # backs an active reservation (Reservation default_scope hides cancelled)

        day_pass.destroy
      end
    end
  end

  private

  # "Today" in the pass's own location time zone, matching how access checks
  # compare a pass's `day` (falls back to the app zone if no location tz).
  def today_for(day_pass)
    tz = day_pass.location&.time_zone
    tz.present? ? Time.current.in_time_zone(tz).to_date : Date.current
  end
end
