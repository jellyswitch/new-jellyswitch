# Rescinds the day-pass product(s) tied to a refunded / voided invoice: destroys
# the invoice's day pass(es) so a refunded pass no longer grants building access
# or blocks bundle redemption, and zeroes the invoice's pack (DayPassBundle) so
# a refunded N-Pack no longer funds entries.
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
#   * Bundle-minted entry passes have invoice_id nil, so the day-pass sweep never
#     matches them. The PACK ITSELF links to its purchase invoice via
#     DayPassBundle#invoice_id (SaveBundle), so refunding a pack zeroes its
#     remaining passes (DayPassBundle#rescind_remaining!) — used days stay
#     history, and no lifecycle emails fire.
class Billing::DayPasses::RescindForInvoice
  include Interactor

  delegate :invoice, to: :context

  def call
    return if invoice.nil?

    ActsAsTenant.with_tenant(invoice.operator) do
      rescind_day_passes
      rescind_bundles
    end
  end

  private

  def rescind_day_passes
    DayPass.where(invoice_id: invoice.id).find_each do |day_pass|
      next if day_pass.day < today_for(day_pass)
      next if day_pass.reservation.present? # backs an active reservation (Reservation default_scope hides cancelled)

      day_pass.destroy
    end
  end

  def rescind_bundles
    DayPassBundle.where(invoice_id: invoice.id).find_each do |bundle|
      bundle.rescind_remaining!(reason: "Refund of invoice ##{invoice.id} — unused pass rescinded")
    end
  end

  # "Today" in the pass's own location time zone, matching how access checks
  # compare a pass's `day` (falls back to the app zone if no location tz).
  def today_for(day_pass)
    tz = day_pass.location&.time_zone
    tz.present? ? Time.current.in_time_zone(tz).to_date : Date.current
  end
end
