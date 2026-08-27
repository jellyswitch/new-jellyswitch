class AddConciergeOfferTextToLocations < ActiveRecord::Migration[7.2]
  # Per-location Concierge offer/promo override. Blank = inherit the
  # operator-level concierge_offer_text (each location can run its own
  # "try a day pass" hook without forking the brand-wide default).
  def change
    add_column :locations, :concierge_offer_text, :string
  end
end
