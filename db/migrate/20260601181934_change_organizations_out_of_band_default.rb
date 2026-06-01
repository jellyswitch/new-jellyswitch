class ChangeOrganizationsOutOfBandDefault < ActiveRecord::Migration[7.1]
  # The previous default of `true` meant every new Organization was created in
  # "we'll send you an invoice" mode by default — and when Billing::Leasing
  # spun up the org's first Stripe subscription, the OutOfBand adapter baked
  # `collection_method: send_invoice` + `days_until_due: 30` into the Stripe
  # record. If an admin (or member) later flipped `out_of_band` to false and
  # added a card, the local flag changed but the Stripe subscription kept its
  # send_invoice mode forever — so Stripe quietly created `open` invoices each
  # cycle without ever attempting to charge.
  #
  # Caught when Wild and Well Studio (org 1429) wasn't charged on 5/30 even
  # though the org showed `out_of_band: false` locally. 40+ other orgs are
  # currently in a similar shape; this migration only changes the default for
  # *new* rows. Existing rows are left as-is — some are intentionally OOB
  # (sponsorships / member-bucket orgs) and shouldn't be silently flipped.
  def change
    change_column_default :organizations, :out_of_band, from: true, to: false
  end
end
